import { HttpStatus, Injectable, Optional, Logger } from "@nestjs/common";
import {
  AccountMode,
  ActorType,
  ContractDirection,
  ContractResult,
  LedgerDirection,
  LedgerTransactionType,
  Prisma,
  type TimedContract,
  type TimedContractSettlement,
} from "@prisma/client";
import { ComplianceService } from "../compliance/compliance.service";
import { IdempotencyService } from "../database/idempotency.service";
import { LedgerService, type LedgerLine } from "../database/ledger.service";
import { OutboxService } from "../database/outbox.service";
import { PrismaService } from "../database/prisma.service";
import { ApiErrorException } from "../http/api-error";
import { DemoPriceService } from "../trading/demo-price.service";
import { proportionalSettlement } from "./proportional-settlement";
import { ContractPriceService } from "./contract-price.service";
import { ControlService } from "../operations/control.service";
import type {
  CreateTimedContractDto,
  TimedContractsQueryDto,
} from "./timed-contracts.dto";

@Injectable()
export class TimedContractsService {
  private dueCursor: string | undefined;
  async terms() {
    const row = await this.prisma.systemConfig.findUnique({
      where: { key: "trading.profitFeeRate" },
    });
    return {
      profitFeeRate: row?.value ?? "0",
      settlementModel: "PROPORTIONAL_V2",
    };
  }
  constructor(
    private readonly prisma: PrismaService,
    private readonly compliance: ComplianceService,
    private readonly ledger: LedgerService,
    private readonly idempotency: IdempotencyService,
    private readonly outbox: OutboxService,
    private readonly prices: DemoPriceService,
    @Optional() private readonly contractPrices?: ContractPriceService,
    @Optional() private readonly controls?: ControlService,
  ) {}

  async create(
    userId: string,
    key: string,
    body: CreateTimedContractDto,
  ): Promise<TimedContractResponse> {
    if (!this.compliance.isEnabled("TIMED_TRADING", body.accountMode)) {
      throw new ApiErrorException(
        "TIMED_TRADING_DISABLED",
        "Timed trading is unavailable for this account.",
        HttpStatus.FORBIDDEN,
      );
    }
    if (body.accountMode === "REAL" && !this.compliance.isVirtual) {
      if (!this.controls)
        throw new ApiErrorException(
          "RELEASE_NOT_APPROVED",
          "Release controls are unavailable.",
          503,
        );
      await this.controls.requireReady();
    }
    // Replays must work even while the external price provider is unavailable.
    const prior = await this.prisma.idempotencyCommand.findUnique({
      where: {
        actorType_actorId_operation_key: {
          actorType: ActorType.USER,
          actorId: userId,
          operation: "TIMED_CONTRACT_CREATE",
          key,
        },
      },
    });
    if (prior) {
      return this.serializable(async (tx) => {
        const claim = await this.idempotency.claim(tx, {
          actorType: ActorType.USER,
          actorId: userId,
          operation: "TIMED_CONTRACT_CREATE",
          key,
          request: body,
        });
        return claim.replay as unknown as TimedContractResponse;
      });
    }
    const sourceInstrument = await this.prisma.instrument.findUnique({
      where: { slug: body.instrumentId },
    });
    if (!sourceInstrument)
      this.notFound("INSTRUMENT_NOT_FOUND", "Instrument not found.");
    const now = new Date();
    // No external HTTP calls while a financial transaction holds row locks.
    const quote = this.contractPrices
      ? await this.contractPrices.at(sourceInstrument, now)
      : this.prices.mark(sourceInstrument, now);
    return this.serializable(async (tx) => {
      const claim = await this.idempotency.claim(tx, {
        actorType: ActorType.USER,
        actorId: userId,
        operation: "TIMED_CONTRACT_CREATE",
        key,
        request: body,
      });
      if (claim.replay) return claim.replay as unknown as TimedContractResponse;
      const account = await tx.account.findUnique({
        where: { userId_mode: { userId, mode: body.accountMode } },
      });
      if (!account) this.notFound("ACCOUNT_NOT_FOUND", "Account not found.");
      await this.ledger.requireOwnedAccount(
        tx,
        userId,
        account.id,
        body.accountMode,
      );
      const instrument = await tx.instrument.findUnique({
        where: { slug: body.instrumentId },
      });
      if (!instrument)
        this.notFound("INSTRUMENT_NOT_FOUND", "Instrument not found.");
      if (
        instrument.baseAsset !== sourceInstrument.baseAsset ||
        instrument.assetClass !== sourceInstrument.assetClass
      ) {
        this.invalid(
          "TRADING_TERMS_CHANGED",
          "Instrument configuration changed. Please retry.",
        );
      }
      if (
        body.accountMode === AccountMode.DEMO || this.compliance.isVirtual
          ? !instrument.demoEnabled
          : !instrument.realEnabled
      ) {
        throw new ApiErrorException(
          "INSTRUMENT_TRADING_DISABLED",
          "This instrument is unavailable for this account mode.",
          HttpStatus.FORBIDDEN,
        );
      }
      if (body.accountMode === AccountMode.REAL && !this.compliance.isVirtual) {
        const user = await tx.user.findUnique({ where: { id: userId } });
        const kyc = await tx.kycCase.findFirst({
          where: { userId, status: "APPROVED" },
        });
        if (!user?.tradingEnabled || !kyc || !this.contractPrices) {
          throw new ApiErrorException(
            "REAL_ACCOUNT_RESTRICTED",
            "Identity verification and trading eligibility are required.",
            403,
          );
        }
      }
      const amount = new Prisma.Decimal(body.investmentAmount);
      const minimumStake = this.compliance.isVirtual ? 0.01 : 10;
      if (
        !amount.isFinite() ||
        amount.lessThan(minimumStake) ||
        amount.decimalPlaces() > 2
      ) {
        this.invalid(
          "INVALID_INVESTMENT_AMOUNT",
          `Minimum stake is $${minimumStake.toFixed(2)}, with at most two decimal places.`,
        );
      }
      const wallet = await this.ledger.lockWallet(tx, account.id);
      if (wallet.availableProjection.lessThan(amount)) {
        this.invalid(
          "INSUFFICIENT_FUNDS",
          "The account has insufficient available funds.",
        );
      }
      const feeConfig = await tx.systemConfig.findUnique({
        where: { key: "trading.profitFeeRate" },
      });
      const feeRate = new Prisma.Decimal(
        typeof feeConfig?.value === "string" ? feeConfig.value : "0",
      );
      if (
        body.expectedProfitFeeRate !== undefined &&
        !feeRate.equals(body.expectedProfitFeeRate)
      ) {
        this.invalid(
          "TRADING_TERMS_CHANGED",
          "The fee changed. Review the trade again.",
        );
      }
      if (
        !feeRate.isFinite() ||
        feeRate.lessThan(0) ||
        feeRate.greaterThan(1)
      ) {
        this.invalid(
          "INVALID_FEE_CONFIGURATION",
          "Trading fee configuration is invalid.",
        );
      }
      if (Date.now() - now.getTime() > 5000) {
        this.invalid(
          "STALE_ENTRY_PRICE",
          "Please retry with a fresh entry price.",
        );
      }
      const expiry = new Date(now.getTime() + body.durationSeconds * 1000);
      const contract = await tx.timedContract.create({
        data: {
          userId,
          accountId: account.id,
          instrumentId: instrument.id,
          idempotencyKey: key,
          direction: body.direction,
          investmentAmount: amount,
          payoutRate: new Prisma.Decimal(0),
          settlementModel: "PROPORTIONAL_V2",
          profitFeeRate: feeRate,
          entryPrice: quote.price,
          entryTimestamp: now,
          expiryTimestamp: expiry,
          entryProviderTimestamp: quote.timestamp,
          entrySequence: sequenceFor(quote.timestamp),
          priceSource: quote.providerId,
        },
      });
      await tx.wallet.update({
        where: { id: wallet.id },
        data: {
          availableProjection: { decrement: amount },
          lockedProjection: { increment: amount },
        },
      });
      const accounts = await this.ledger.ensureAccountLedgerAccounts(
        tx,
        account.id,
        body.accountMode,
      );
      await this.ledger.post(tx, {
        type: LedgerTransactionType.TRADE,
        idempotencyKey: `timed-open:${contract.id}`,
        description: `${body.accountMode} proportional contract opened`,
        reference: contract.id,
        entries: [
          {
            ledgerAccountId: accounts.available,
            direction: LedgerDirection.DEBIT,
            amount,
          },
          {
            ledgerAccountId: accounts.locked,
            direction: LedgerDirection.CREDIT,
            amount,
          },
        ],
      });
      const response = contractResponse(contract, instrument.slug);
      await this.idempotency.complete(tx, claim.command.id, response);
      await this.outbox.enqueueAccount(tx, userId, {
        aggregateType: "TimedContract",
        aggregateId: contract.id,
        eventType: "timed_contract.created",
        payload: response,
      });
      return response;
    });
  }

  async settleDueBatch(
    limit = 50,
  ): Promise<{ examined: number; settled: number }> {
    const due = await this.prisma.timedContract.findMany({
      where: {
        result: ContractResult.PENDING,
        expiryTimestamp: { lte: new Date() },
        ...(this.dueCursor ? { id: { gt: this.dueCursor } } : {}),
      },
      orderBy: { id: "asc" },
      take: Math.max(1, Math.min(limit, 100)),
      select: { id: true },
    });
    this.dueCursor = due.at(-1)?.id;
    let settled = 0;
    for (const candidate of due) {
      try {
        if (await this.settleOne(candidate.id)) settled += 1;
      } catch (error) {
        Logger.warn(
          `Contract ${candidate.id} remains pending: ${error instanceof Error ? error.name : "Error"}`,
          "TimedSettlement",
        );
      }
    }
    return { examined: due.length, settled };
  }

  async list(userId: string, query: TimedContractsQueryDto) {
    const account = await this.prisma.account.findUnique({
      where: { userId_mode: { userId, mode: query.accountMode } },
      select: { id: true },
    });
    if (!account) this.notFound("ACCOUNT_NOT_FOUND", "Account not found.");
    const rows = await this.prisma.timedContract.findMany({
      where: {
        userId,
        accountId: account.id,
        ...(query.result ? { result: query.result } : {}),
      },
      include: { instrument: { select: { slug: true } }, settlement: true },
      orderBy: [{ entryTimestamp: "desc" }, { id: "desc" }],
      ...(query.cursor ? { cursor: { id: query.cursor }, skip: 1 } : {}),
      take: query.limit,
    });
    return {
      items: rows.map((row) => contractResponse(row, row.instrument.slug)),
      nextCursor: rows.length === query.limit ? rows.at(-1)?.id : null,
    };
  }

  private async settleOne(contractId: string): Promise<boolean> {
    const candidate = await this.prisma.timedContract.findUnique({
      where: { id: contractId },
      include: { instrument: true },
    });
    if (
      !candidate ||
      candidate.result !== ContractResult.PENDING ||
      candidate.expiryTimestamp.getTime() > Date.now()
    )
      return false;
    const quote = candidate.priceSource.startsWith("BINANCE_1S_V1:")
      ? await this.contractPrices!.at(
          candidate.instrument,
          candidate.expiryTimestamp,
        )
      : this.prices.mark(candidate.instrument, candidate.expiryTimestamp);
    return this.serializable(async (tx) => {
      await tx.$queryRaw`SELECT id FROM timed_contracts WHERE id = ${contractId}::uuid FOR UPDATE`;
      const contract = await tx.timedContract.findUnique({
        where: { id: contractId },
        include: { instrument: true, account: true },
      });
      if (!contract || contract.result !== ContractResult.PENDING) return false;
      if (
        contract.expiryTimestamp.getTime() !==
        candidate.expiryTimestamp.getTime()
      ) {
        this.invalid(
          "CONTRACT_TERMS_CHANGED",
          "Contract expiry changed during settlement.",
        );
      }
      if (
        contract.priceSource.startsWith("BINANCE_1S_V1:") &&
        quote.providerId !== contract.priceSource
      ) {
        this.invalid(
          "PRICE_SOURCE_MISMATCH",
          "The original settlement source is required.",
        );
      }
      const comparison = quote.price.comparedTo(contract.entryPrice);
      const won =
        (contract.direction === ContractDirection.UP && comparison > 0) ||
        (contract.direction === ContractDirection.DOWN && comparison < 0);
      const result =
        comparison === 0
          ? ContractResult.DRAW
          : won
            ? ContractResult.WIN
            : ContractResult.LOSS;
      const proportional =
        contract.settlementModel === "PROPORTIONAL_V2"
          ? proportionalSettlement(
              contract.investmentAmount,
              contract.entryPrice,
              quote.price,
              contract.direction,
              contract.profitFeeRate,
            )
          : null;
      const payout =
        proportional?.payout ??
        (result === ContractResult.WIN
          ? contract.investmentAmount.mul(
              new Prisma.Decimal(1).plus(contract.payoutRate),
            )
          : result === ContractResult.DRAW
            ? contract.investmentAmount
            : new Prisma.Decimal(0));
      const wallet = await this.ledger.lockWallet(tx, contract.accountId);
      if (wallet.lockedProjection.lessThan(contract.investmentAmount)) {
        throw new ApiErrorException(
          "LEDGER_PROJECTION_MISMATCH",
          "Locked funds do not reconcile with this contract.",
          HttpStatus.CONFLICT,
        );
      }
      await tx.wallet.update({
        where: { id: wallet.id },
        data: {
          lockedProjection: { decrement: contract.investmentAmount },
          ...(payout.isPositive()
            ? { availableProjection: { increment: payout } }
            : {}),
        },
      });
      const accounts = await this.ledger.ensureAccountLedgerAccounts(
        tx,
        contract.accountId,
        contract.account.mode,
      );
      const entries: LedgerLine[] = [
        {
          ledgerAccountId: accounts.locked,
          direction: LedgerDirection.DEBIT,
          amount: contract.investmentAmount,
        },
      ];
      if (payout.greaterThan(0)) {
        entries.push({
          ledgerAccountId: accounts.available,
          direction: LedgerDirection.CREDIT,
          amount: payout,
        });
      }
      const pnl =
        proportional?.grossPnl ?? payout.minus(contract.investmentAmount);
      if (proportional && proportional.fee.greaterThan(0)) {
        const fees = await tx.ledgerAccount.upsert({
          where: { code: `PV:${contract.account.mode}:PROFIT_FEES:USD` },
          update: {},
          create: {
            code: `PV:${contract.account.mode}:PROFIT_FEES:USD`,
            name: "Profit fees",
            currencyCode: "USD",
            mode: contract.account.mode,
            type: "REVENUE",
          },
        });
        entries.push({
          ledgerAccountId: fees.id,
          direction: LedgerDirection.CREDIT,
          amount: proportional.fee,
        });
      }
      const counterparty =
        contract.account.mode === AccountMode.REAL
          ? await tx.ledgerAccount.upsert({
              where: { code: "PV:REAL:COUNTERPARTY_PNL:USD" },
              update: {},
              create: {
                code: "PV:REAL:COUNTERPARTY_PNL:USD",
                name: "Zettax counterparty P&L",
                currencyCode: "USD",
                mode: AccountMode.REAL,
                type: "EXPENSE",
              },
            })
          : { id: accounts.control };
      if (pnl.greaterThan(0)) {
        entries.push({
          ledgerAccountId: counterparty.id,
          direction: LedgerDirection.DEBIT,
          amount: pnl,
        });
      } else if (pnl.lessThan(0)) {
        entries.push({
          ledgerAccountId: counterparty.id,
          direction: LedgerDirection.CREDIT,
          amount: pnl.abs(),
        });
      }
      await this.ledger.post(tx, {
        type: LedgerTransactionType.TRADE_SETTLEMENT,
        idempotencyKey: `timed-settle:${contract.id}`,
        description: `${contract.account.mode} timed contract ${result.toLowerCase()}`,
        reference: contract.id,
        entries,
      });
      const settlement = await tx.timedContractSettlement.create({
        data: {
          contractId: contract.id,
          expiryPrice: quote.price,
          expiryTimestamp: contract.expiryTimestamp,
          expiryProviderTimestamp: quote.timestamp,
          expirySequence: sequenceFor(quote.timestamp),
          priceSource: quote.providerId,
          result,
          payoutAmount: payout,
          grossPnl: pnl,
          feeAmount: proportional?.fee ?? new Prisma.Decimal(0),
        },
      });
      const updated = await tx.timedContract.update({
        where: { id: contract.id },
        data: { result },
      });
      const response = contractResponse(
        { ...updated, settlement },
        contract.instrument.slug,
      );
      await this.outbox.enqueueAccount(tx, contract.userId, {
        aggregateType: "TimedContract",
        aggregateId: contract.id,
        eventType: "timed_contract.settled",
        payload: response,
      });
      return true;
    });
  }

  private async serializable<T>(
    work: (tx: Prisma.TransactionClient) => Promise<T>,
  ): Promise<T> {
    for (let attempt = 0; attempt < 3; attempt += 1) {
      try {
        return await this.prisma.$transaction(work, {
          isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
          timeout: 30_000,
          maxWait: 10_000,
        });
      } catch (error) {
        const retryable =
          error instanceof Prisma.PrismaClientKnownRequestError &&
          (error.code === "P2034" ||
            (error.code === "P2010" && error.meta?.code === "40001"));
        if (!retryable || attempt === 2) throw error;
      }
    }
    throw new Error("Unreachable serializable retry state");
  }

  private invalid(code: string, message: string): never {
    throw new ApiErrorException(code, message, HttpStatus.BAD_REQUEST);
  }

  private notFound(code: string, message: string): never {
    throw new ApiErrorException(code, message, HttpStatus.NOT_FOUND);
  }
}

function sequenceFor(timestamp: Date): bigint {
  return BigInt(Math.floor(timestamp.getTime() / 15_000));
}

function contractResponse(
  contract: TimedContract & { settlement?: TimedContractSettlement | null },
  instrumentId: string,
) {
  return {
    id: contract.id,
    accountId: contract.accountId,
    instrumentId,
    direction: contract.direction,
    investmentAmount: contract.investmentAmount.toFixed(2),
    payoutRate: contract.payoutRate.toFixed(),
    settlementModel: contract.settlementModel,
    profitFeeRate: contract.profitFeeRate.toFixed(),
    entryPrice: contract.entryPrice.toFixed(),
    entryTimestamp: contract.entryTimestamp.toISOString(),
    expiryTimestamp: contract.expiryTimestamp.toISOString(),
    priceSource: contract.priceSource,
    result: contract.result,
    settlement: contract.settlement
      ? {
          expiryPrice: contract.settlement.expiryPrice.toFixed(),
          result: contract.settlement.result,
          payoutAmount: contract.settlement.payoutAmount.toFixed(2),
          grossPnl: contract.settlement.grossPnl.toFixed(2),
          feeAmount: contract.settlement.feeAmount.toFixed(2),
          settledAt: contract.settlement.settledAt.toISOString(),
        }
      : null,
    simulated: !contract.priceSource.startsWith("BINANCE_1S_V1:"),
  };
}

type TimedContractResponse = ReturnType<typeof contractResponse>;
