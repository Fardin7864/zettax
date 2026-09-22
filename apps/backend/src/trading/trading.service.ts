import { HttpStatus, Injectable } from "@nestjs/common";
import {
  AccountMode,
  ActorType,
  LedgerDirection,
  LedgerTransactionType,
  OrderSide,
  OrderStatus,
  PositionStatus,
  Prisma,
} from "@prisma/client";
import { IdempotencyService } from "../database/idempotency.service";
import { LedgerService, type LedgerLine } from "../database/ledger.service";
import { OutboxService } from "../database/outbox.service";
import { PrismaService } from "../database/prisma.service";
import { ApiErrorException } from "../http/api-error";
import { ComplianceService } from "../compliance/compliance.service";
import { ExecutionProviderService } from "./execution-provider.service";
import { DemoPriceService } from "./demo-price.service";
import type {
  CreateOrderDto,
  OrdersQueryDto,
  PositionsQueryDto,
} from "./trading.dto";

type JsonRecord = Record<string, unknown>;

@Injectable()
export class TradingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly ledger: LedgerService,
    private readonly idempotency: IdempotencyService,
    private readonly outbox: OutboxService,
    private readonly providers: ExecutionProviderService,
    private readonly demoPrices: DemoPriceService,
    private readonly compliance: ComplianceService,
  ) {}

  async createOrder(userId: string, key: string, body: CreateOrderDto) {
    if (body.accountMode === AccountMode.REAL && !this.compliance.isVirtual) {
      const instrument = await this.prisma.instrument.findUnique({
        where: { slug: body.instrumentId },
        select: { assetClass: true },
      });
      if (!instrument)
        this.notFound("INSTRUMENT_NOT_FOUND", "Instrument not found.");
      this.providers.providerForReal(instrument.assetClass);
    }
    const request = { ...body, idempotencyKey: key };
    return this.runSerializable(async (tx) => {
      const claim = await this.idempotency.claim(tx, {
        actorType: ActorType.USER,
        actorId: userId,
        operation: "ORDER_CREATE",
        key,
        request,
      });
      if (claim.replay) return claim.replay as JsonRecord;

      const account = await tx.account.findUnique({
        where: { userId_mode: { userId, mode: body.accountMode } },
        select: { id: true, userId: true, mode: true, status: true },
      });
      if (!account) this.notFound("ACCOUNT_NOT_FOUND", "Account not found.");
      await this.ledger.requireOwnedAccount(
        tx,
        userId,
        account.id,
        body.accountMode,
      );
      const user = await tx.user.findUnique({
        where: { id: userId },
        select: { tradingEnabled: true },
      });
      if (!user?.tradingEnabled) {
        throw new ApiErrorException(
          "TRADING_DISABLED",
          "Trading is disabled for this account.",
          HttpStatus.FORBIDDEN,
        );
      }
      const instrument = await tx.instrument.findUnique({
        where: { slug: body.instrumentId },
        include: { config: true },
      });
      if (!instrument)
        this.notFound("INSTRUMENT_NOT_FOUND", "Instrument not found.");
      const virtualReal =
        body.accountMode === AccountMode.REAL && this.compliance.isVirtual;
      if (
        !instrument.demoEnabled ||
        (body.accountMode !== AccountMode.DEMO && !virtualReal)
      ) {
        throw new ApiErrorException(
          "INSTRUMENT_TRADING_DISABLED",
          "This instrument is not available for the selected account.",
          HttpStatus.FORBIDDEN,
        );
      }
      const quantity = this.decimal(
        body.quantity,
        instrument.quantityPrecision,
        "quantity",
      );
      const quote = this.demoPrices.quote(instrument, body.side);
      const exposure = quote.price
        .mul(quantity)
        .toDecimalPlaces(2, Prisma.Decimal.ROUND_HALF_UP);
      if (!exposure.isPositive())
        this.invalid("ORDER_VALUE_TOO_SMALL", "Order value is too small.");
      if (instrument.config) {
        if (!virtualReal && exposure.lessThan(instrument.config.minimumTrade)) {
          this.invalid(
            "ORDER_BELOW_MINIMUM",
            "Order value is below the configured minimum.",
          );
        }
        if (
          !virtualReal &&
          exposure.greaterThan(instrument.config.maximumTrade)
        ) {
          this.invalid(
            "ORDER_ABOVE_MAXIMUM",
            "Order value is above the configured maximum.",
          );
        }
      }
      const wallet = await this.ledger.lockWallet(tx, account.id);
      if (wallet.availableProjection.lessThan(exposure)) {
        this.invalid(
          "INSUFFICIENT_FUNDS",
          "The account has insufficient available funds.",
        );
      }
      const accounts = await this.ledger.ensureAccountLedgerAccounts(
        tx,
        account.id,
        account.mode,
      );
      const order = await tx.order.create({
        data: {
          userId,
          accountId: account.id,
          instrumentId: instrument.id,
          clientOrderId: body.clientOrderId,
          idempotencyKey: key,
          side: body.side,
          orderType: "MARKET",
          quantity,
          requestedPrice: quote.price,
          filledQuantity: quantity,
          averageFillPrice: quote.price,
          status: OrderStatus.FILLED,
          providerOrderId: `${quote.providerId}:${body.clientOrderId}`,
          executions: {
            create: {
              providerId: `${quote.providerId}:${body.clientOrderId}`,
              quantity,
              price: quote.price,
              executedAt: quote.timestamp,
            },
          },
        },
      });
      const position = await tx.position.create({
        data: {
          accountId: account.id,
          instrumentId: instrument.id,
          side: body.side,
          quantity,
          averageEntry: quote.price,
        },
      });
      await tx.wallet.update({
        where: { id: wallet.id },
        data: {
          availableProjection: { decrement: exposure },
          lockedProjection: { increment: exposure },
        },
      });
      await this.ledger.post(tx, {
        type: LedgerTransactionType.TRADE,
        idempotencyKey: `order-open:${order.id}`,
        description: `${virtualReal ? "Virtual" : "Demo"} ${body.side} position opened`,
        reference: order.id,
        entries: [
          {
            ledgerAccountId: accounts.available,
            direction: LedgerDirection.DEBIT,
            amount: exposure,
          },
          {
            ledgerAccountId: accounts.locked,
            direction: LedgerDirection.CREDIT,
            amount: exposure,
          },
        ],
      });
      const response = this.orderResponse(order, instrument.slug, position.id);
      await this.idempotency.complete(tx, claim.command.id, response);
      await this.outbox.enqueueAccount(tx, userId, {
        aggregateType: "Order",
        aggregateId: order.id,
        eventType: "order.filled",
        payload: response,
      });
      return response;
    });
  }

  async closePosition(userId: string, positionId: string, key: string) {
    return this.runSerializable(async (tx) => {
      const claim = await this.idempotency.claim(tx, {
        actorType: ActorType.USER,
        actorId: userId,
        operation: "POSITION_CLOSE",
        key,
        request: { positionId },
      });
      if (claim.replay) return claim.replay as JsonRecord;
      const position = await tx.position.findUnique({
        where: { id: positionId },
        include: { account: true, instrument: true },
      });
      if (!position || position.account.userId !== userId) {
        this.notFound("POSITION_NOT_FOUND", "Position not found.");
      }
      await this.ledger.requireOwnedAccount(
        tx,
        userId,
        position.accountId,
        position.account.mode,
      );
      if (
        position.account.mode !== AccountMode.DEMO &&
        !this.compliance.isVirtual
      ) {
        this.providers.providerForReal(position.instrument.assetClass);
      }
      if (position.status !== PositionStatus.OPEN) {
        throw new ApiErrorException(
          "POSITION_ALREADY_CLOSED",
          "The position has already been closed.",
          HttpStatus.CONFLICT,
        );
      }
      const closingSide =
        position.side === OrderSide.BUY ? OrderSide.SELL : OrderSide.BUY;
      const quote = this.demoPrices.quote(position.instrument, closingSide);
      const notional = position.averageEntry
        .mul(position.quantity)
        .toDecimalPlaces(2, Prisma.Decimal.ROUND_HALF_UP);
      const direction = position.side === OrderSide.BUY ? 1 : -1;
      let pnl = quote.price
        .minus(position.averageEntry)
        .mul(position.quantity)
        .mul(direction)
        .toDecimalPlaces(2, Prisma.Decimal.ROUND_HALF_UP);
      if (pnl.lessThan(notional.negated())) pnl = notional.negated();
      const settlement = notional.plus(pnl);
      const wallet = await this.ledger.lockWallet(tx, position.accountId);
      if (wallet.lockedProjection.lessThan(notional)) {
        throw new ApiErrorException(
          "LEDGER_PROJECTION_MISMATCH",
          "Locked funds do not reconcile with this position.",
          HttpStatus.CONFLICT,
        );
      }
      const accounts = await this.ledger.ensureAccountLedgerAccounts(
        tx,
        position.accountId,
        position.account.mode,
      );
      await tx.wallet.update({
        where: { id: wallet.id },
        data: {
          availableProjection: { increment: settlement },
          lockedProjection: { decrement: notional },
        },
      });
      const entries: LedgerLine[] = [
        {
          ledgerAccountId: accounts.locked,
          direction: LedgerDirection.DEBIT,
          amount: notional,
        },
      ];
      if (settlement.isPositive()) {
        entries.push({
          ledgerAccountId: accounts.available,
          direction: LedgerDirection.CREDIT,
          amount: settlement,
        });
      }
      if (pnl.isPositive()) {
        entries.push({
          ledgerAccountId: accounts.control,
          direction: LedgerDirection.DEBIT,
          amount: pnl,
        });
      } else if (pnl.isNegative()) {
        entries.push({
          ledgerAccountId: accounts.control,
          direction: LedgerDirection.CREDIT,
          amount: pnl.abs(),
        });
      }
      await this.ledger.post(tx, {
        type: LedgerTransactionType.TRADE_SETTLEMENT,
        idempotencyKey: `position-close:${position.id}`,
        description: `${position.account.mode === AccountMode.REAL ? "Virtual" : "Demo"} position settled`,
        reference: position.id,
        entries,
      });
      await tx.order.create({
        data: {
          userId,
          accountId: position.accountId,
          instrumentId: position.instrumentId,
          clientOrderId: `position-close:${position.id}`,
          idempotencyKey: key,
          side: closingSide,
          orderType: "MARKET",
          quantity: position.quantity,
          requestedPrice: quote.price,
          filledQuantity: position.quantity,
          averageFillPrice: quote.price,
          status: OrderStatus.FILLED,
          providerOrderId: `${quote.providerId}:close:${position.id}`,
          executions: {
            create: {
              providerId: `${quote.providerId}:close:${position.id}`,
              quantity: position.quantity,
              price: quote.price,
              executedAt: quote.timestamp,
            },
          },
        },
      });
      const updated = await tx.position.update({
        where: { id: position.id },
        data: {
          status: PositionStatus.CLOSED,
          realizedPnl: pnl,
          closedAt: quote.timestamp,
        },
      });
      const response = this.positionResponse(
        updated,
        position.instrument.slug,
        quote.price,
      );
      await this.idempotency.complete(tx, claim.command.id, response);
      await this.outbox.enqueueAccount(tx, userId, {
        aggregateType: "Position",
        aggregateId: position.id,
        eventType: "position.closed",
        payload: response,
      });
      return response;
    });
  }

  async listOrders(userId: string, query: OrdersQueryDto) {
    const account = await this.ownedAccount(userId, query.accountMode);
    const rows = await this.prisma.order.findMany({
      where: {
        userId,
        accountId: account.id,
        ...(query.status ? { status: query.status } : {}),
      },
      include: { instrument: { select: { slug: true } } },
      orderBy: { createdAt: "desc" },
      take: query.limit,
    });
    return {
      items: rows.map((row) => this.orderResponse(row, row.instrument.slug)),
    };
  }

  async listPositions(userId: string, query: PositionsQueryDto) {
    const account = await this.ownedAccount(userId, query.accountMode);
    const rows = await this.prisma.position.findMany({
      where: {
        accountId: account.id,
        ...(query.status ? { status: query.status } : {}),
      },
      include: { instrument: true },
      orderBy: { openedAt: "desc" },
    });
    return {
      items: rows.map((row) => {
        const mark = this.demoPrices.quote(row.instrument, row.side).price;
        return this.positionResponse(row, row.instrument.slug, mark);
      }),
    };
  }

  async listTrades(userId: string, query: OrdersQueryDto) {
    const account = await this.ownedAccount(userId, query.accountMode);
    const rows = await this.prisma.execution.findMany({
      where: { order: { userId, accountId: account.id } },
      include: {
        order: { include: { instrument: { select: { slug: true } } } },
      },
      orderBy: { executedAt: "desc" },
      take: query.limit,
    });
    return {
      items: rows.map((row) => ({
        id: row.id,
        orderId: row.orderId,
        instrumentId: row.order.instrument.slug,
        side: row.order.side,
        quantity: row.quantity.toFixed(),
        price: row.price.toFixed(),
        fee: row.fee.toFixed(),
        executedAt: row.executedAt.toISOString(),
        simulated: row.providerId?.startsWith("PRIMEVEST_DEMO:") ?? false,
      })),
    };
  }

  private async ownedAccount(userId: string, mode: AccountMode) {
    const account = await this.prisma.account.findUnique({
      where: { userId_mode: { userId, mode } },
      select: { id: true, mode: true },
    });
    if (!account) this.notFound("ACCOUNT_NOT_FOUND", "Account not found.");
    return account;
  }

  private decimal(value: string, precision: number, field: string) {
    const decimal = new Prisma.Decimal(value);
    if (!decimal.isPositive() || decimal.decimalPlaces() > precision) {
      this.invalid("INVALID_ORDER_QUANTITY", `${field} has invalid precision.`);
    }
    return decimal;
  }

  private orderResponse(
    order: {
      id: string;
      clientOrderId: string;
      side: OrderSide;
      orderType: string;
      quantity: Prisma.Decimal;
      filledQuantity: Prisma.Decimal;
      averageFillPrice: Prisma.Decimal | null;
      fees: Prisma.Decimal;
      status: OrderStatus;
      createdAt: Date;
      updatedAt: Date;
    },
    instrumentId: string,
    positionId?: string,
  ) {
    return {
      id: order.id,
      clientOrderId: order.clientOrderId,
      instrumentId,
      side: order.side,
      orderType: order.orderType,
      quantity: order.quantity.toFixed(),
      filledQuantity: order.filledQuantity.toFixed(),
      averageFillPrice: order.averageFillPrice?.toFixed() ?? null,
      fees: order.fees.toFixed(),
      status: order.status,
      simulated: true,
      positionId: positionId ?? null,
      createdAt: order.createdAt.toISOString(),
      updatedAt: order.updatedAt.toISOString(),
    };
  }

  private positionResponse(
    position: {
      id: string;
      side: OrderSide;
      quantity: Prisma.Decimal;
      averageEntry: Prisma.Decimal;
      realizedPnl: Prisma.Decimal;
      status: PositionStatus;
      openedAt: Date;
      closedAt: Date | null;
    },
    instrumentId: string,
    mark: Prisma.Decimal,
  ) {
    const direction = position.side === OrderSide.BUY ? 1 : -1;
    const unrealized =
      position.status === PositionStatus.OPEN
        ? mark
            .minus(position.averageEntry)
            .mul(position.quantity)
            .mul(direction)
        : new Prisma.Decimal(0);
    return {
      id: position.id,
      instrumentId,
      side: position.side,
      quantity: position.quantity.toFixed(),
      averageEntry: position.averageEntry.toFixed(),
      markPrice: mark.toFixed(),
      realizedPnl: position.realizedPnl.toFixed(2),
      unrealizedPnl: unrealized.toFixed(2),
      status: position.status,
      openedAt: position.openedAt.toISOString(),
      closedAt: position.closedAt?.toISOString() ?? null,
    };
  }

  private async runSerializable<T>(
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
    throw new Error("Unreachable transaction retry state");
  }

  private invalid(code: string, message: string): never {
    throw new ApiErrorException(code, message, HttpStatus.BAD_REQUEST);
  }

  private notFound(code: string, message: string): never {
    throw new ApiErrorException(code, message, HttpStatus.NOT_FOUND);
  }
}
