import { HttpStatus, Injectable } from "@nestjs/common";
import {
  AccountMode,
  ActorType,
  LedgerDirection,
  LedgerTransactionType,
  OrderStatus,
  Prisma,
} from "@prisma/client";
import { ConfigService } from "@nestjs/config";
import { IdempotencyService } from "../database/idempotency.service";
import { LedgerService } from "../database/ledger.service";
import { OutboxService } from "../database/outbox.service";
import { PrismaService } from "../database/prisma.service";
import { ApiErrorException } from "../http/api-error";

type TransactionCursor = { postedAt: string; id: string };
type DemoResetResponse = {
  accountId: string;
  mode: "DEMO";
  available: string;
  locked: string;
  reset: boolean;
  ledgerTransactionId: string | null;
};

const activeOrderStatuses: OrderStatus[] = [
  OrderStatus.CREATED,
  OrderStatus.PENDING,
  OrderStatus.ACCEPTED,
  OrderStatus.PARTIALLY_FILLED,
];

@Injectable()
export class AccountsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly ledger: LedgerService,
    private readonly idempotency: IdempotencyService,
    private readonly outbox: OutboxService,
  ) {}

  async list(userId: string) {
    const accounts = await this.prisma.account.findMany({
      where: { userId },
      orderBy: { mode: "asc" },
      include: {
        wallets: { orderBy: { currencyCode: "asc" } },
        _count: { select: { positions: { where: { status: "OPEN" } } } },
      },
    });
    return accounts.map((account) => ({
      id: account.id,
      mode: account.mode,
      status: account.status,
      wallets: account.wallets.map((wallet) => ({
        currencyCode: wallet.currencyCode,
        available: wallet.availableProjection.toFixed(2),
        locked: wallet.lockedProjection.toFixed(2),
        equity: wallet.availableProjection
          .plus(wallet.lockedProjection)
          .toFixed(2),
      })),
      openPositionCount: account._count.positions,
      createdAt: account.createdAt,
    }));
  }

  async transactions(
    userId: string,
    mode: AccountMode,
    limit: number,
    encodedCursor?: string,
  ) {
    const account = await this.prisma.account.findUnique({
      where: { userId_mode: { userId, mode } },
      select: { id: true },
    });
    if (!account) {
      throw new ApiErrorException(
        "ACCOUNT_NOT_FOUND",
        "The requested account was not found.",
        HttpStatus.NOT_FOUND,
      );
    }
    const cursor = encodedCursor ? this.decodeCursor(encodedCursor) : undefined;
    const rows = await this.prisma.ledgerTransaction.findMany({
      where: {
        entries: { some: { ledgerAccount: { accountId: account.id } } },
        ...(cursor
          ? {
              OR: [
                { postedAt: { lt: new Date(cursor.postedAt) } },
                {
                  postedAt: new Date(cursor.postedAt),
                  id: { lt: cursor.id },
                },
              ],
            }
          : {}),
      },
      orderBy: [{ postedAt: "desc" }, { id: "desc" }],
      take: limit + 1,
      select: {
        id: true,
        type: true,
        reference: true,
        description: true,
        postedAt: true,
        reversalOfId: true,
        entries: {
          where: { ledgerAccount: { accountId: account.id } },
          orderBy: { createdAt: "asc" },
          select: {
            id: true,
            direction: true,
            amount: true,
            ledgerAccount: {
              select: { code: true, name: true, currencyCode: true },
            },
          },
        },
      },
    });
    const hasMore = rows.length > limit;
    const page = hasMore ? rows.slice(0, limit) : rows;
    const last = page.at(-1);
    return {
      accountId: account.id,
      mode,
      items: page.map((row) => ({
        id: row.id,
        type: row.type,
        reference: row.reference,
        description: row.description,
        postedAt: row.postedAt,
        reversalOfId: row.reversalOfId,
        entries: row.entries.map((entry) => ({
          id: entry.id,
          direction: entry.direction,
          amount: entry.amount.toFixed(2),
          accountCode: entry.ledgerAccount.code,
          accountName: entry.ledgerAccount.name,
          currencyCode: entry.ledgerAccount.currencyCode,
        })),
      })),
      nextCursor:
        hasMore && last
          ? this.encodeCursor({
              postedAt: last.postedAt.toISOString(),
              id: last.id,
            })
          : null,
    };
  }

  async resetDemo(
    userId: string,
    idempotencyKey: string,
  ): Promise<DemoResetResponse> {
    return this.withSerializableRetry(async (tx) => {
      const account = await tx.account.findUnique({
        where: { userId_mode: { userId, mode: AccountMode.DEMO } },
        select: { id: true },
      });
      if (!account) {
        throw new ApiErrorException(
          "ACCOUNT_NOT_FOUND",
          "The demo account was not found.",
          HttpStatus.NOT_FOUND,
        );
      }
      await tx.$queryRaw`SELECT id FROM accounts WHERE id = ${account.id}::uuid FOR UPDATE`;
      const claimed = await this.idempotency.claim(tx, {
        actorType: ActorType.USER,
        actorId: userId,
        operation: "accounts.demo.reset",
        key: idempotencyKey,
        request: { accountMode: AccountMode.DEMO },
      });
      if (claimed.replay !== null) return this.demoResetReplay(claimed.replay);

      const [activeOrders, openPositions, activeContracts] = await Promise.all([
        tx.order.count({
          where: { accountId: account.id, status: { in: activeOrderStatuses } },
        }),
        tx.position.count({
          where: { accountId: account.id, status: "OPEN" },
        }),
        tx.timedContract.count({
          where: { accountId: account.id, result: "PENDING" },
        }),
      ]);
      if (activeOrders || openPositions || activeContracts) {
        throw new ApiErrorException(
          "DEMO_RESET_BLOCKED",
          "Close active demo trades before resetting the account.",
          HttpStatus.CONFLICT,
        );
      }

      const wallet = await this.ledger.lockWallet(tx, account.id, "BDT");
      if (!wallet.lockedProjection.isZero()) {
        throw new ApiErrorException(
          "DEMO_RESET_BLOCKED",
          "Locked demo funds must be released before reset.",
          HttpStatus.CONFLICT,
        );
      }
      const accounts = await this.ledger.ensureAccountLedgerAccounts(
        tx,
        account.id,
        AccountMode.DEMO,
      );
      await this.assertWalletProjection(
        tx,
        accounts.available,
        wallet.availableProjection,
      );
      const target = this.demoInitialBalance();
      const difference = target.minus(wallet.availableProjection);
      let ledgerTransactionId: string | null = null;
      if (!difference.isZero()) {
        const amount = difference.abs();
        const increasing = difference.isPositive();
        const journal = await this.ledger.post(tx, {
          type: LedgerTransactionType.DEMO_RESET,
          idempotencyKey: `demo-reset:${userId}:${idempotencyKey}`,
          description: "Reset non-withdrawable demo funds",
          entries: increasing
            ? [
                {
                  ledgerAccountId: accounts.control,
                  direction: LedgerDirection.DEBIT,
                  amount,
                },
                {
                  ledgerAccountId: accounts.available,
                  direction: LedgerDirection.CREDIT,
                  amount,
                },
              ]
            : [
                {
                  ledgerAccountId: accounts.available,
                  direction: LedgerDirection.DEBIT,
                  amount,
                },
                {
                  ledgerAccountId: accounts.control,
                  direction: LedgerDirection.CREDIT,
                  amount,
                },
              ],
        });
        ledgerTransactionId = journal.id;
        await tx.wallet.update({
          where: { id: wallet.id },
          data: { availableProjection: target },
        });
      }
      const response: DemoResetResponse = {
        accountId: account.id,
        mode: "DEMO",
        available: target.toFixed(2),
        locked: "0.00",
        reset: !difference.isZero(),
        ledgerTransactionId,
      };
      await this.idempotency.complete(tx, claimed.command.id, response);
      await this.outbox.enqueueAccount(tx, userId, {
        aggregateType: "Account",
        aggregateId: account.id,
        eventType: "account.demo.reset",
        payload: response,
      });
      return response;
    });
  }

  private async assertWalletProjection(
    tx: Prisma.TransactionClient,
    ledgerAccountId: string,
    projection: Prisma.Decimal,
  ): Promise<void> {
    const totals = await tx.ledgerEntry.groupBy({
      by: ["direction"],
      where: { ledgerAccountId },
      _sum: { amount: true },
    });
    const credit =
      totals.find((row) => row.direction === LedgerDirection.CREDIT)?._sum
        .amount ?? new Prisma.Decimal(0);
    const debit =
      totals.find((row) => row.direction === LedgerDirection.DEBIT)?._sum
        .amount ?? new Prisma.Decimal(0);
    if (!credit.minus(debit).equals(projection)) {
      throw new ApiErrorException(
        "LEDGER_RECONCILIATION_FAILED",
        "The wallet projection does not reconcile with the ledger.",
        HttpStatus.CONFLICT,
      );
    }
  }

  private demoInitialBalance(): Prisma.Decimal {
    try {
      const value = new Prisma.Decimal(
        this.config.get<string>("DEMO_INITIAL_BALANCE_BDT") ?? "100000.00",
      );
      if (value.isPositive() && value.decimalPlaces() <= 2) return value;
    } catch {
      // Invalid development configuration safely falls back to the contract.
    }
    return new Prisma.Decimal("100000.00");
  }

  private async withSerializableRetry<T>(
    operation: (tx: Prisma.TransactionClient) => Promise<T>,
  ): Promise<T> {
    for (let attempt = 1; attempt <= 3; attempt += 1) {
      try {
        return await this.prisma.$transaction(operation, {
          isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
        });
      } catch (error) {
        const retryable =
          error instanceof Prisma.PrismaClientKnownRequestError &&
          (error.code === "P2034" ||
            error.code === "P2002" ||
            (error.code === "P2010" && error.meta?.code === "40001"));
        if (!retryable || attempt === 3) throw error;
      }
    }
    throw new Error("Unreachable serializable retry state");
  }

  private encodeCursor(cursor: TransactionCursor): string {
    return Buffer.from(JSON.stringify(cursor)).toString("base64url");
  }

  private decodeCursor(value: string): TransactionCursor {
    try {
      const parsed: unknown = JSON.parse(
        Buffer.from(value, "base64url").toString("utf8"),
      );
      if (
        typeof parsed === "object" &&
        parsed !== null &&
        "postedAt" in parsed &&
        "id" in parsed &&
        typeof parsed.postedAt === "string" &&
        typeof parsed.id === "string" &&
        Number.isFinite(new Date(parsed.postedAt).getTime()) &&
        /^[0-9a-f-]{36}$/i.test(parsed.id)
      ) {
        return { postedAt: parsed.postedAt, id: parsed.id };
      }
    } catch {
      // The caller receives a stable validation error below.
    }
    throw new ApiErrorException(
      "PAGINATION_CURSOR_INVALID",
      "The pagination cursor is invalid.",
      HttpStatus.BAD_REQUEST,
    );
  }

  private demoResetReplay(value: Prisma.JsonValue): DemoResetResponse {
    if (
      typeof value === "object" &&
      value !== null &&
      !Array.isArray(value) &&
      value.mode === "DEMO" &&
      typeof value.accountId === "string" &&
      typeof value.available === "string" &&
      typeof value.locked === "string" &&
      typeof value.reset === "boolean" &&
      (typeof value.ledgerTransactionId === "string" ||
        value.ledgerTransactionId === null)
    ) {
      return {
        accountId: value.accountId,
        mode: "DEMO",
        available: value.available,
        locked: value.locked,
        reset: value.reset,
        ledgerTransactionId: value.ledgerTransactionId,
      };
    }
    throw new ApiErrorException(
      "IDEMPOTENCY_RESPONSE_INVALID",
      "The stored command response is invalid.",
      HttpStatus.INTERNAL_SERVER_ERROR,
    );
  }
}
