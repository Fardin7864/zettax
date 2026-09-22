import { Injectable } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { PrismaService } from "../database/prisma.service";

@Injectable()
export class AccountEventsService {
  constructor(private readonly prisma: PrismaService) {}

  async latestSequence(userId: string): Promise<bigint> {
    const stream = await this.prisma.accountEventStream.findUnique({
      where: { userId },
      select: { lastSequence: true },
    });
    return stream?.lastSequence ?? 0n;
  }

  async recover(userId: string, afterSequence: bigint, limit = 500) {
    const events = await this.prisma.accountEvent.findMany({
      where: { userId, sequence: { gt: afterSequence } },
      orderBy: { sequence: "asc" },
      take: Math.max(1, Math.min(limit, 1_000)),
    });
    return events.map(accountEventResponse);
  }

  async snapshot(userId: string) {
    return this.prisma.$transaction(
      async (tx) => {
        const [
          stream,
          accounts,
          orders,
          positions,
          contracts,
          funding,
          notifications,
        ] = await Promise.all([
          tx.accountEventStream.findUnique({
            where: { userId },
            select: { lastSequence: true },
          }),
          tx.account.findMany({
            where: { userId },
            orderBy: { mode: "asc" },
            include: { wallets: { orderBy: { currencyCode: "asc" } } },
          }),
          tx.order.findMany({
            where: { userId },
            orderBy: { createdAt: "desc" },
            take: 50,
            include: { instrument: { select: { slug: true } } },
          }),
          tx.position.findMany({
            where: { account: { userId }, status: "OPEN" },
            orderBy: { openedAt: "desc" },
            include: { instrument: { select: { slug: true } } },
          }),
          tx.timedContract.findMany({
            where: { userId, result: "PENDING" },
            orderBy: { expiryTimestamp: "asc" },
            include: { instrument: { select: { slug: true } } },
          }),
          Promise.all([
            tx.depositRequest.findMany({
              where: { userId },
              orderBy: { createdAt: "desc" },
              take: 20,
            }),
            tx.withdrawalRequest.findMany({
              where: { userId },
              orderBy: { createdAt: "desc" },
              take: 20,
            }),
          ]),
          tx.notification.findMany({
            where: { userId },
            orderBy: { createdAt: "desc" },
            take: 50,
          }),
        ]);

        return {
          schemaVersion: 1,
          snapshotVersion: (stream?.lastSequence ?? 0n).toString(),
          serverTime: new Date().toISOString(),
          accounts: accounts.map((account) => ({
            id: account.id,
            mode: account.mode,
            status: account.status,
            wallets: account.wallets.map((wallet) => ({
              currencyCode: wallet.currencyCode,
              available: wallet.availableProjection.toFixed(2),
              locked: wallet.lockedProjection.toFixed(2),
            })),
          })),
          orders: orders.map((order) => ({
            id: order.id,
            accountId: order.accountId,
            instrumentId: order.instrument.slug,
            side: order.side,
            orderType: order.orderType,
            quantity: order.quantity.toFixed(),
            filledQuantity: order.filledQuantity.toFixed(),
            averageFillPrice: order.averageFillPrice?.toFixed() ?? null,
            status: order.status,
            createdAt: order.createdAt.toISOString(),
            updatedAt: order.updatedAt.toISOString(),
          })),
          positions: positions.map((position) => ({
            id: position.id,
            accountId: position.accountId,
            instrumentId: position.instrument.slug,
            side: position.side,
            quantity: position.quantity.toFixed(),
            averageEntry: position.averageEntry.toFixed(),
            realizedPnl: position.realizedPnl.toFixed(2),
            status: position.status,
            openedAt: position.openedAt.toISOString(),
          })),
          timedContracts: contracts.map((contract) => ({
            id: contract.id,
            accountId: contract.accountId,
            instrumentId: contract.instrument.slug,
            direction: contract.direction,
            investmentAmount: contract.investmentAmount.toFixed(2),
            payoutRate: contract.payoutRate.toFixed(),
            entryPrice: contract.entryPrice.toFixed(),
            expiryTimestamp: contract.expiryTimestamp.toISOString(),
            result: contract.result,
          })),
          deposits: funding[0].map(financialRequestResponse),
          withdrawals: funding[1].map(financialRequestResponse),
          notifications: notifications.map((notification) => ({
            id: notification.id,
            type: notification.type,
            titleKey: notification.titleKey,
            bodyKey: notification.bodyKey,
            data: notification.data,
            readAt: notification.readAt?.toISOString() ?? null,
            createdAt: notification.createdAt.toISOString(),
          })),
        };
      },
      {
        isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead,
        timeout: 30_000,
        maxWait: 10_000,
      },
    );
  }
}

export function accountEventResponse(event: {
  id: string;
  sequence: bigint;
  eventType: string;
  payload: Prisma.JsonValue;
  occurredAt: Date;
}) {
  return {
    schemaVersion: 1,
    id: event.id,
    sequence: event.sequence.toString(),
    type: event.eventType,
    payload: event.payload,
    occurredAt: event.occurredAt.toISOString(),
  };
}

function financialRequestResponse(request: {
  id: string;
  accountId: string;
  amount: Prisma.Decimal;
  status: string;
  statusVersion: number;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    id: request.id,
    accountId: request.accountId,
    amount: request.amount.toFixed(2),
    status: request.status,
    statusVersion: request.statusVersion,
    createdAt: request.createdAt.toISOString(),
    updatedAt: request.updatedAt.toISOString(),
  };
}
