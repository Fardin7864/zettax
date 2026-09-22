import { HttpStatus, Injectable } from "@nestjs/common";
import {
  AccountMode,
  LedgerAccountType,
  LedgerDirection,
  LedgerTransactionType,
  Prisma,
  type Wallet,
} from "@prisma/client";
import { ApiErrorException } from "../http/api-error";

export type LedgerLine = {
  ledgerAccountId: string;
  direction: LedgerDirection;
  amount: Prisma.Decimal;
};

export type LedgerPostInput = {
  type: LedgerTransactionType;
  idempotencyKey: string;
  description: string;
  reference?: string;
  reversalOfId?: string;
  entries: LedgerLine[];
};

@Injectable()
export class LedgerService {
  async requireOwnedAccount(
    tx: Prisma.TransactionClient,
    userId: string,
    accountId: string,
    mode: AccountMode,
  ) {
    const account = await tx.account.findUnique({
      where: { id_userId: { id: accountId, userId } },
      select: { id: true, userId: true, mode: true, status: true },
    });
    if (!account || account.mode !== mode) {
      throw new ApiErrorException(
        "ACCOUNT_NOT_FOUND",
        "The requested account was not found.",
        HttpStatus.NOT_FOUND,
      );
    }
    if (account.status !== "ACTIVE") {
      throw new ApiErrorException(
        "ACCOUNT_RESTRICTED",
        "The requested account is not active.",
        HttpStatus.FORBIDDEN,
      );
    }
    return account;
  }

  async lockWallet(
    tx: Prisma.TransactionClient,
    accountId: string,
    currencyCode = "BDT",
  ): Promise<Wallet> {
    await tx.$queryRaw`SELECT id FROM wallets WHERE account_id = ${accountId}::uuid AND currency_code = ${currencyCode} FOR UPDATE`;
    const wallet = await tx.wallet.findUnique({
      where: { accountId_currencyCode: { accountId, currencyCode } },
    });
    if (!wallet) {
      throw new ApiErrorException(
        "WALLET_NOT_FOUND",
        "The requested wallet was not found.",
        HttpStatus.NOT_FOUND,
      );
    }
    return wallet;
  }

  async ensureAccountLedgerAccounts(
    tx: Prisma.TransactionClient,
    accountId: string,
    mode: AccountMode,
    currencyCode = "BDT",
  ): Promise<{ control: string; available: string; locked: string }> {
    const currency = await tx.currency.findUnique({
      where: { code: currencyCode },
      select: { code: true },
    });
    if (!currency) {
      throw new ApiErrorException(
        "CURRENCY_NOT_FOUND",
        "The account currency is not configured.",
        HttpStatus.CONFLICT,
      );
    }
    const prefix = "USER";
    const controlCode =
      mode === AccountMode.DEMO
        ? `PV:DEMO:FUNDING:${currencyCode}`
        : `PV:CASH_CLEARING:${currencyCode}`;
    const [control, available, locked] = await Promise.all([
      tx.ledgerAccount.upsert({
        where: { code: controlCode },
        create: {
          code: controlCode,
          name:
            mode === AccountMode.DEMO
              ? "Demo funding control"
              : "Customer cash clearing",
          currencyCode,
          mode,
          type: LedgerAccountType.ASSET,
        },
        update: { mode },
        select: { id: true },
      }),
      tx.ledgerAccount.upsert({
        where: { code: `PV:${prefix}:${accountId}:AVAILABLE:${currencyCode}` },
        create: {
          code: `PV:${prefix}:${accountId}:AVAILABLE:${currencyCode}`,
          name: `${mode === AccountMode.DEMO ? "Demo" : "Customer"} funds available`,
          currencyCode,
          accountId,
          mode,
          type: LedgerAccountType.LIABILITY,
        },
        update: {},
        select: { id: true },
      }),
      tx.ledgerAccount.upsert({
        where: { code: `PV:${prefix}:${accountId}:LOCKED:${currencyCode}` },
        create: {
          code: `PV:${prefix}:${accountId}:LOCKED:${currencyCode}`,
          name: `${mode === AccountMode.DEMO ? "Demo" : "Customer"} funds locked`,
          currencyCode,
          accountId,
          mode,
          type: LedgerAccountType.LIABILITY,
        },
        update: {},
        select: { id: true },
      }),
    ]);
    return {
      control: control.id,
      available: available.id,
      locked: locked.id,
    };
  }

  async post(
    tx: Prisma.TransactionClient,
    input: LedgerPostInput,
  ): Promise<{ id: string }> {
    this.assertBalanced(input.entries);
    const accountIds = [
      ...new Set(input.entries.map((line) => line.ledgerAccountId)),
    ];
    if (accountIds.length !== input.entries.length) {
      throw this.invalidLedger(
        "A ledger account may appear only once per journal.",
      );
    }
    const accounts = await tx.ledgerAccount.findMany({
      where: { id: { in: accountIds } },
      select: { id: true, accountId: true, currencyCode: true, mode: true },
    });
    if (accounts.length !== accountIds.length) {
      throw this.invalidLedger("Every ledger account must exist.");
    }
    if (new Set(accounts.map((account) => account.currencyCode)).size !== 1) {
      throw this.invalidLedger("A journal cannot mix currencies.");
    }
    const ownedAccountIds = new Set(
      accounts.flatMap((account) =>
        account.accountId ? [account.accountId] : [],
      ),
    );
    if (ownedAccountIds.size > 1) {
      throw this.invalidLedger("A journal cannot mix customer accounts.");
    }
    const modes = new Set(
      accounts.flatMap((account) => (account.mode ? [account.mode] : [])),
    );
    if (modes.size > 1) {
      throw this.invalidLedger("A journal cannot mix DEMO and REAL accounts.");
    }

    const journal = await tx.ledgerTransaction.create({
      data: {
        type: input.type,
        idempotencyKey: input.idempotencyKey,
        description: input.description,
        reference: input.reference ?? null,
        ...(input.reversalOfId
          ? { reversalOf: { connect: { id: input.reversalOfId } } }
          : {}),
      },
      select: { id: true },
    });
    await tx.$queryRaw(Prisma.sql`
      SELECT set_config(
        'primevest.posting_journal_id',
        ${journal.id},
        true
      )
    `);
    await tx.ledgerEntry.createMany({
      data: input.entries.map((entry) => ({
        transactionId: journal.id,
        ledgerAccountId: entry.ledgerAccountId,
        direction: entry.direction,
        amount: entry.amount,
      })),
    });
    return journal;
  }

  private assertBalanced(entries: LedgerLine[]): void {
    const debit = entries
      .filter((entry) => entry.direction === LedgerDirection.DEBIT)
      .reduce((sum, entry) => sum.plus(entry.amount), new Prisma.Decimal(0));
    const credit = entries
      .filter((entry) => entry.direction === LedgerDirection.CREDIT)
      .reduce((sum, entry) => sum.plus(entry.amount), new Prisma.Decimal(0));
    if (
      entries.length < 2 ||
      entries.some((entry) => !entry.amount.isPositive()) ||
      !debit.equals(credit) ||
      !debit.isPositive()
    ) {
      throw this.invalidLedger(
        "Ledger journals require equal positive debit and credit totals.",
      );
    }
  }

  private invalidLedger(message: string): ApiErrorException {
    return new ApiErrorException(
      "LEDGER_UNBALANCED",
      message,
      HttpStatus.INTERNAL_SERVER_ERROR,
    );
  }
}
