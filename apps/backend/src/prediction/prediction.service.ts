import { Injectable, Logger } from "@nestjs/common";
import {
  AccountMode,
  LedgerDirection,
  LedgerTransactionType,
  PredictionPositionResult,
  PredictionQuestionStatus,
  Prisma,
} from "@prisma/client";
import { ComplianceService } from "../compliance/compliance.service";
import { LedgerService, type LedgerLine } from "../database/ledger.service";
import { OutboxService } from "../database/outbox.service";
import { PrismaService } from "../database/prisma.service";
import { ApiErrorException } from "../http/api-error";
import { ControlService } from "../operations/control.service";
import { ContractPriceService } from "../timed-contracts/contract-price.service";
import type {
  CreatePredictionQuestionDto,
  PlacePredictionDto,
  PredictionQuestionsQueryDto,
} from "./prediction.dto";
import { allocatePredictionPool, predictionOutcome } from "./pool";
import { PredictionGateway } from "./prediction.gateway";

const questionInclude = {
  instrument: { select: { slug: true, symbol: true, pricePrecision: true } },
  creator: { select: { profile: { select: { fullName: true } } } },
} as const;
type QuestionRow = Prisma.PredictionQuestionGetPayload<{
  include: typeof questionInclude;
}>;

@Injectable()
export class PredictionService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly compliance: ComplianceService,
    private readonly ledger: LedgerService,
    private readonly outbox: OutboxService,
    private readonly prices: ContractPriceService,
    private readonly controls: ControlService,
    private readonly gateway: PredictionGateway,
  ) {}

  availability() {
    return {
      demo: true,
      real: this.realEnabled(),
      poolFeeRate: "0",
      settlement: "Last archived one-second close before the UTC expiry",
    };
  }

  private realEnabled() {
    return (
      this.compliance.mode === "PRODUCTION_APPROVED" &&
      this.compliance.isEnabled("REAL_TRADING") &&
      this.compliance.isEnabled("PREDICTIONS") &&
      Boolean(process.env.PREDICTION_REAL_APPROVAL_REFERENCE?.trim())
    );
  }

  private question(row: QuestionRow) {
    const yesDemo = row.yesDemoPool.toNumber();
    const noDemo = row.noDemoPool.toNumber();
    const yesReal = row.yesRealPool.toNumber();
    const noReal = row.noRealPool.toNumber();
    const poolShare = (yes: number, no: number) =>
      yes + no === 0 ? 50 : Math.round((yes / (yes + no)) * 1000) / 10;
    return {
      id: row.id,
      creator: row.creatorId
        ? row.creator?.profile?.fullName || "Zettax member"
        : "Zettax",
      instrumentId: row.instrument.slug,
      symbol: row.instrument.symbol,
      pricePrecision: row.instrument.pricePrecision,
      condition: row.condition,
      targetPrice: row.targetPrice.toFixed(),
      referencePrice: row.referencePrice.toFixed(),
      referenceSource: row.referenceSource,
      referenceTimestamp: row.referenceTimestamp,
      expiresAt: row.expiresAt,
      status: row.status,
      outcome: row.outcome,
      settlementPrice: row.settlementPrice?.toFixed() ?? null,
      settlementSource: row.settlementSource,
      yesDemoPool: row.yesDemoPool.toFixed(2),
      noDemoPool: row.noDemoPool.toFixed(2),
      yesRealPool: row.yesRealPool.toFixed(2),
      noRealPool: row.noRealPool.toFixed(2),
      demoYesPoolShare: poolShare(yesDemo, noDemo),
      realYesPoolShare: poolShare(yesReal, noReal),
      createdAt: row.createdAt,
    };
  }

  async list(query: PredictionQuestionsQueryDto) {
    const rows = await this.prisma.predictionQuestion.findMany({
      where: query.status ? { status: query.status } : {},
      include: questionInclude,
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      ...(query.cursor ? { cursor: { id: query.cursor }, skip: 1 } : {}),
      take: 21,
    });
    const items = rows.slice(0, 20).map((row) => this.question(row));
    return { items, nextCursor: rows.length > 20 ? items.at(-1)?.id : null };
  }

  async get(id: string) {
    const row = await this.prisma.predictionQuestion.findUnique({
      where: { id },
      include: questionInclude,
    });
    if (!row)
      this.error("QUESTION_NOT_FOUND", "Prediction question not found.", 404);
    return this.question(row);
  }

  async create(creatorId: string | null, body: CreatePredictionQuestionDto) {
    const now = new Date();
    const expiry = new Date(body.expiresAt);
    if (
      !Number.isFinite(expiry.getTime()) ||
      expiry.getTime() < now.getTime() + 10 * 60_000 ||
      expiry.getTime() > now.getTime() + 30 * 24 * 60 * 60_000
    ) {
      this.error(
        "EXPIRY_INVALID",
        "Choose an expiry from 10 minutes to 30 days ahead.",
        400,
      );
    }
    const instrument = await this.prisma.instrument.findUnique({
      where: { slug: body.instrumentId },
    });
    if (
      !instrument ||
      instrument.assetClass !== "CRYPTO" ||
      !instrument.demoEnabled
    ) {
      this.error(
        "INSTRUMENT_UNAVAILABLE",
        "Choose an available crypto market.",
        400,
      );
    }
    if (creatorId) {
      const active = await this.prisma.predictionQuestion.count({
        where: {
          creatorId,
          status: PredictionQuestionStatus.OPEN,
          expiresAt: { gt: now },
        },
      });
      if (active >= 5)
        this.error(
          "QUESTION_LIMIT",
          "You can have up to five open questions.",
          429,
        );
    }
    const target = new Prisma.Decimal(body.targetPrice);
    if (
      !target.isFinite() ||
      target.lessThanOrEqualTo(0) ||
      target.decimalPlaces() > instrument.pricePrecision
    ) {
      this.error(
        "TARGET_INVALID",
        "Enter a positive target using the market's price precision.",
        400,
      );
    }
    const reference = await this.prices.at(instrument, now);
    if (
      target.lessThan(reference.price.mul("0.5")) ||
      target.greaterThan(reference.price.mul("1.5"))
    ) {
      this.error(
        "TARGET_OUT_OF_RANGE",
        "Target price must be within 50% of the latest archived price.",
        400,
      );
    }
    const created = await this.prisma.predictionQuestion.create({
      data: {
        creatorId,
        instrumentId: instrument.id,
        condition: body.condition,
        targetPrice: target,
        referencePrice: reference.price,
        referenceSource: reference.providerId,
        referenceTimestamp: reference.timestamp,
        expiresAt: expiry,
      },
      include: questionInclude,
    });
    this.gateway.created(created.id);
    return this.question(created);
  }

  /** Keep a small set of objective demo questions available without manual entry. */
  async ensurePlatformQuestions() {
    const now = new Date();
    let created = 0;
    for (const slug of ["btc-usd", "eth-usd"]) {
      const instrument = await this.prisma.instrument.findUnique({
        where: { slug },
      });
      if (!instrument?.demoEnabled) continue;
      const existing = await this.prisma.predictionQuestion.count({
        where: {
          creatorId: null,
          instrumentId: instrument.id,
          status: PredictionQuestionStatus.OPEN,
          expiresAt: { gt: now },
        },
      });
      if (existing > 0) continue;
      try {
        const reference = await this.prices.at(instrument, now);
        await this.create(null, {
          instrumentId: slug,
          condition: "ABOVE",
          targetPrice: reference.price.toFixed(instrument.pricePrecision),
          expiresAt: new Date(now.getTime() + 60 * 60_000).toISOString(),
        });
        created++;
      } catch (error) {
        Logger.warn(
          `Platform question for ${slug} could not be created: ${error instanceof Error ? error.name : "UnknownError"}`,
          "PredictionQuestions",
        );
      }
    }
    return { created };
  }

  async myPositions(userId: string) {
    const rows = await this.prisma.predictionPosition.findMany({
      where: { userId },
      include: { question: { include: questionInclude } },
      orderBy: { createdAt: "desc" },
      take: 100,
    });
    return rows.map((row) => ({
      id: row.id,
      question: this.question(row.question),
      accountMode: row.mode,
      side: row.side,
      stake: row.stake.toFixed(2),
      payoutAmount: row.payoutAmount?.toFixed(2) ?? null,
      result: row.result,
      createdAt: row.createdAt,
      settledAt: row.settledAt,
    }));
  }

  async place(
    userId: string,
    questionId: string,
    key: string,
    body: PlacePredictionDto,
  ) {
    const mode =
      body.accountMode === "REAL" ? AccountMode.REAL : AccountMode.DEMO;
    const stake = new Prisma.Decimal(body.stake);
    const minimum = mode === AccountMode.REAL ? 10 : 0.01;
    if (
      !stake.isFinite() ||
      stake.lessThan(minimum) ||
      stake.greaterThan(100_000) ||
      stake.decimalPlaces() > 2
    ) {
      this.error(
        "STAKE_INVALID",
        `Stake must be between $${minimum.toFixed(2)} and $100,000.00.`,
        400,
      );
    }
    if (mode === AccountMode.REAL) {
      if (!this.realEnabled())
        this.error(
          "REAL_PREDICTIONS_DISABLED",
          "Real-money predictions are not approved for this market.",
          403,
        );
      await this.controls.requireReady();
    }
    const response = await this.serializable(async (tx) => {
      const replay = await tx.predictionPosition.findUnique({
        where: { userId_idempotencyKey: { userId, idempotencyKey: key } },
      });
      if (replay) {
        if (
          replay.questionId !== questionId ||
          replay.mode !== mode ||
          replay.side !== body.side ||
          !replay.stake.equals(stake)
        ) {
          this.error(
            "IDEMPOTENCY_KEY_REUSED",
            "This request key was used for another prediction.",
            409,
          );
        }
        return this.positionResponse(replay);
      }
      await tx.$queryRaw`SELECT id FROM prediction_questions WHERE id = ${questionId}::uuid FOR UPDATE`;
      const question = await tx.predictionQuestion.findUnique({
        where: { id: questionId },
        include: { instrument: true },
      });
      if (!question || question.status !== PredictionQuestionStatus.OPEN) {
        this.error(
          "QUESTION_CLOSED",
          "This prediction question is closed.",
          409,
        );
      }
      if (question.expiresAt.getTime() <= Date.now()) {
        this.error(
          "QUESTION_EXPIRED",
          "This prediction question has expired.",
          409,
        );
      }
      if (
        mode === AccountMode.REAL
          ? !question.instrument.realEnabled
          : !question.instrument.demoEnabled
      ) {
        this.error(
          "INSTRUMENT_UNAVAILABLE",
          "This market is unavailable for the selected account.",
          403,
        );
      }
      const count = await tx.predictionPosition.count({
        where: { questionId },
      });
      if (count >= 500)
        this.error(
          "QUESTION_FULL",
          "This question has reached its participant limit.",
          409,
        );
      const account = await tx.account.findUnique({
        where: { userId_mode: { userId, mode } },
      });
      if (!account)
        this.error(
          "ACCOUNT_NOT_FOUND",
          "The selected account is unavailable.",
          404,
        );
      await this.ledger.requireOwnedAccount(tx, userId, account.id, mode);
      if (mode === AccountMode.REAL) {
        const [user, kyc] = await Promise.all([
          tx.user.findUnique({
            where: { id: userId },
            select: { tradingEnabled: true },
          }),
          tx.kycCase.findFirst({
            where: { userId, status: "APPROVED" },
            select: { id: true },
          }),
        ]);
        if (!user?.tradingEnabled || !kyc) {
          this.error(
            "REAL_ACCOUNT_RESTRICTED",
            "Identity verification and trading eligibility are required.",
            403,
          );
        }
      }
      const wallet = await this.ledger.lockWallet(tx, account.id);
      if (wallet.availableProjection.lessThan(stake)) {
        this.error(
          "INSUFFICIENT_FUNDS",
          "The selected account has insufficient available funds.",
          400,
        );
      }
      const position = await tx.predictionPosition.create({
        data: {
          questionId,
          userId,
          accountId: account.id,
          mode,
          side: body.side,
          stake,
          idempotencyKey: key,
        },
      });
      await tx.wallet.update({
        where: { id: wallet.id },
        data: {
          availableProjection: { decrement: stake },
          lockedProjection: { increment: stake },
        },
      });
      const poolField =
        `${body.side.toLowerCase()}${mode === AccountMode.DEMO ? "Demo" : "Real"}Pool` as
          "yesDemoPool" | "noDemoPool" | "yesRealPool" | "noRealPool";
      await tx.predictionQuestion.update({
        where: { id: questionId },
        data: { [poolField]: { increment: stake } },
      });
      const accounts = await this.ledger.ensureAccountLedgerAccounts(
        tx,
        account.id,
        mode,
      );
      await this.ledger.post(tx, {
        type: LedgerTransactionType.TRADE,
        idempotencyKey: `prediction-open:${position.id}`,
        description: `${mode} prediction stake locked`,
        reference: position.id,
        entries: [
          {
            ledgerAccountId: accounts.available,
            direction: LedgerDirection.DEBIT,
            amount: stake,
          },
          {
            ledgerAccountId: accounts.locked,
            direction: LedgerDirection.CREDIT,
            amount: stake,
          },
        ],
      });
      const response = this.positionResponse(position);
      await this.outbox.enqueueAccount(tx, userId, {
        aggregateType: "PredictionPosition",
        aggregateId: position.id,
        eventType: "prediction.position.created",
        payload: response,
      });
      return response;
    });
    this.gateway.changed(questionId);
    return response;
  }

  private positionResponse(row: {
    id: string;
    questionId: string;
    mode: AccountMode;
    side: string;
    stake: Prisma.Decimal;
    payoutAmount: Prisma.Decimal | null;
    result: PredictionPositionResult;
    createdAt: Date;
    settledAt: Date | null;
  }) {
    return {
      id: row.id,
      questionId: row.questionId,
      accountMode: row.mode,
      side: row.side,
      stake: row.stake.toFixed(2),
      payoutAmount: row.payoutAmount?.toFixed(2) ?? null,
      result: row.result,
      createdAt: row.createdAt,
      settledAt: row.settledAt,
    };
  }

  async settleDueBatch(limit = 5) {
    const due = await this.prisma.predictionQuestion.findMany({
      where: {
        status: PredictionQuestionStatus.OPEN,
        expiresAt: { lte: new Date() },
      },
      orderBy: [{ expiresAt: "asc" }, { id: "asc" }],
      take: Math.max(1, Math.min(limit, 20)),
      select: { id: true },
    });
    let settled = 0;
    for (const item of due) {
      try {
        if (await this.settleOne(item.id)) settled++;
      } catch (error) {
        Logger.warn(
          `Question ${item.id} remains pending: ${error instanceof Error ? error.name : "UnknownError"}`,
          "PredictionSettlement",
        );
      }
    }
    return { examined: due.length, settled };
  }

  private async settleOne(questionId: string): Promise<boolean> {
    const candidate = await this.prisma.predictionQuestion.findUnique({
      where: { id: questionId },
      include: { instrument: true },
    });
    if (
      !candidate ||
      candidate.status !== PredictionQuestionStatus.OPEN ||
      candidate.expiresAt.getTime() > Date.now()
    )
      return false;
    const quote = await this.prices.at(
      candidate.instrument,
      candidate.expiresAt,
    );
    if (quote.providerId !== candidate.referenceSource) {
      this.error(
        "PRICE_SOURCE_MISMATCH",
        "The original archived price source is required.",
        503,
      );
    }
    const settled = await this.serializable(async (tx) => {
      await tx.$queryRaw`SELECT id FROM prediction_questions WHERE id = ${questionId}::uuid FOR UPDATE`;
      const question = await tx.predictionQuestion.findUnique({
        where: { id: questionId },
        include: { positions: { include: { account: true } } },
      });
      if (!question || question.status !== PredictionQuestionStatus.OPEN)
        return false;
      if (question.expiresAt.getTime() !== candidate.expiresAt.getTime()) {
        this.error(
          "QUESTION_TERMS_CHANGED",
          "Question expiry changed during settlement.",
          409,
        );
      }
      const outcome = predictionOutcome(
        quote.price,
        question.targetPrice,
        question.condition,
      );
      const payouts = new Map<string, Prisma.Decimal>();
      for (const mode of [AccountMode.DEMO, AccountMode.REAL]) {
        const entries = question.positions.filter(
          (position) => position.mode === mode,
        );
        const allocated = allocatePredictionPool(
          entries.map((position) => ({
            id: position.id,
            side: position.side,
            stake: position.stake,
          })),
          outcome,
        );
        const stakes = entries.reduce(
          (sum, position) => sum.plus(position.stake),
          new Prisma.Decimal(0),
        );
        const paid = [...allocated.values()].reduce(
          (sum, value) => sum.plus(value),
          new Prisma.Decimal(0),
        );
        if (!stakes.equals(paid))
          throw new Error("Prediction pool does not reconcile");
        for (const [id, amount] of allocated) payouts.set(id, amount);
      }
      const ordered = [...question.positions].sort((a, b) => {
        const aGain = payouts.get(a.id)!.minus(a.stake);
        const bGain = payouts.get(b.id)!.minus(b.stake);
        return aGain.comparedTo(bGain) || a.id.localeCompare(b.id);
      });
      const settledAt = new Date();
      for (const position of ordered) {
        const payout = payouts.get(position.id)!;
        const wallet = await this.ledger.lockWallet(tx, position.accountId);
        if (wallet.lockedProjection.lessThan(position.stake)) {
          this.error(
            "LEDGER_PROJECTION_MISMATCH",
            "Locked prediction funds do not reconcile.",
            409,
          );
        }
        await tx.wallet.update({
          where: { id: wallet.id },
          data: {
            lockedProjection: { decrement: position.stake },
            ...(payout.isPositive()
              ? { availableProjection: { increment: payout } }
              : {}),
          },
        });
        const accounts = await this.ledger.ensureAccountLedgerAccounts(
          tx,
          position.accountId,
          position.mode,
        );
        const entries: LedgerLine[] = [
          {
            ledgerAccountId: accounts.locked,
            direction: LedgerDirection.DEBIT,
            amount: position.stake,
          },
        ];
        if (payout.isPositive())
          entries.push({
            ledgerAccountId: accounts.available,
            direction: LedgerDirection.CREDIT,
            amount: payout,
          });
        const difference = payout.minus(position.stake);
        if (!difference.isZero()) {
          const pool = await tx.ledgerAccount.upsert({
            where: { code: `PV:PREDICTION:${position.mode}:POOL:USD` },
            update: {},
            create: {
              code: `PV:PREDICTION:${position.mode}:POOL:USD`,
              name: `${position.mode} prediction pool`,
              currencyCode: "USD",
              mode: position.mode,
              type: "LIABILITY",
            },
            select: { id: true },
          });
          entries.push({
            ledgerAccountId: pool.id,
            direction: difference.isPositive()
              ? LedgerDirection.DEBIT
              : LedgerDirection.CREDIT,
            amount: difference.abs(),
          });
        }
        await this.ledger.post(tx, {
          type: LedgerTransactionType.TRADE_SETTLEMENT,
          idempotencyKey: `prediction-settle:${position.id}`,
          description: `${position.mode} prediction pool settlement`,
          reference: position.id,
          entries,
        });
        const result = payout.equals(position.stake)
          ? PredictionPositionResult.REFUNDED
          : position.side === outcome
            ? PredictionPositionResult.WON
            : PredictionPositionResult.LOST;
        const updated = await tx.predictionPosition.update({
          where: { id: position.id },
          data: { payoutAmount: payout, result, settledAt },
        });
        await this.outbox.enqueueAccount(tx, position.userId, {
          aggregateType: "PredictionPosition",
          aggregateId: position.id,
          eventType: "prediction.position.settled",
          payload: this.positionResponse(updated),
        });
      }
      await tx.predictionQuestion.update({
        where: { id: questionId },
        data: {
          status: PredictionQuestionStatus.SETTLED,
          outcome,
          settlementPrice: quote.price,
          settlementSource: quote.providerId,
          settlementTimestamp: quote.timestamp,
        },
      });
      return true;
    });
    if (settled) this.gateway.changed(questionId);
    return settled;
  }

  private error(code: string, message: string, status: number): never {
    throw new ApiErrorException(code, message, status);
  }

  private async serializable<T>(
    work: (tx: Prisma.TransactionClient) => Promise<T>,
  ): Promise<T> {
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        return await this.prisma.$transaction(work, {
          isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
          timeout: 120_000,
        });
      } catch (error) {
        if (
          !(error instanceof Prisma.PrismaClientKnownRequestError) ||
          !["P2034", "P2002"].includes(error.code) ||
          attempt === 2
        )
          throw error;
      }
    }
    throw new Error("Prediction transaction unavailable");
  }
}
