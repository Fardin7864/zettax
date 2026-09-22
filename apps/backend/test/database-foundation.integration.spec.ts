import {
  LedgerAccountType,
  LedgerDirection,
  LedgerTransactionType,
  PrismaClient,
} from "@prisma/client";
import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

const enabled = process.env.RUN_DATABASE_INTEGRATION === "true";
const suite = enabled ? describe : describe.skip;
const prisma = new PrismaClient();

suite("PostgreSQL financial constraints", () => {
  beforeAll(() => prisma.$connect());
  afterAll(() => prisma.$disconnect());

  it("rejects a journal with no balanced entries at commit", async () => {
    await expect(
      prisma.$transaction((tx) =>
        tx.ledgerTransaction.create({
          data: {
            type: LedgerTransactionType.ADJUSTMENT,
            idempotencyKey: `integration:unbalanced:${randomUUID()}`,
            description: "must roll back",
          },
        }),
      ),
    ).rejects.toBeDefined();
  });

  it("prevents mutation of a posted balanced journal", async () => {
    const suffix = randomUUID();
    await expect(
      prisma.$transaction(async (tx) => {
        const [debit, credit] = await Promise.all([
          tx.ledgerAccount.create({
            data: {
              code: `PV:INTEGRATION:DEBIT:${suffix}`,
              name: "Integration debit",
              currencyCode: "BDT",
              type: LedgerAccountType.ASSET,
            },
          }),
          tx.ledgerAccount.create({
            data: {
              code: `PV:INTEGRATION:CREDIT:${suffix}`,
              name: "Integration credit",
              currencyCode: "BDT",
              type: LedgerAccountType.LIABILITY,
            },
          }),
        ]);
        const journal = await tx.ledgerTransaction.create({
          data: {
            type: LedgerTransactionType.ADJUSTMENT,
            idempotencyKey: `integration:immutable:${suffix}`,
            description: "must remain immutable",
            entries: {
              create: [
                {
                  ledgerAccountId: debit.id,
                  direction: LedgerDirection.DEBIT,
                  amount: "1.00",
                },
                {
                  ledgerAccountId: credit.id,
                  direction: LedgerDirection.CREDIT,
                  amount: "1.00",
                },
              ],
            },
          },
        });
        await tx.ledgerTransaction.update({
          where: { id: journal.id },
          data: { description: "forbidden mutation" },
        });
      }),
    ).rejects.toBeDefined();
  });

  it("prevents balanced entries being appended after a journal is posted", async () => {
    const suffix = randomUUID();
    const posted = await prisma.$transaction(async (tx) => {
      const [debit, credit] = await Promise.all([
        tx.ledgerAccount.create({
          data: {
            code: `PV:INTEGRATION:LATE:DEBIT:${suffix}`,
            name: "Late-entry debit",
            currencyCode: "BDT",
            type: LedgerAccountType.ASSET,
          },
        }),
        tx.ledgerAccount.create({
          data: {
            code: `PV:INTEGRATION:LATE:CREDIT:${suffix}`,
            name: "Late-entry credit",
            currencyCode: "BDT",
            type: LedgerAccountType.LIABILITY,
          },
        }),
      ]);
      const journal = await tx.ledgerTransaction.create({
        data: {
          type: LedgerTransactionType.ADJUSTMENT,
          idempotencyKey: `integration:late-entry:${suffix}`,
          description: "posted journal",
          entries: {
            create: [
              {
                ledgerAccountId: debit.id,
                direction: LedgerDirection.DEBIT,
                amount: "1.00",
              },
              {
                ledgerAccountId: credit.id,
                direction: LedgerDirection.CREDIT,
                amount: "1.00",
              },
            ],
          },
        },
      });
      return { journalId: journal.id, debitId: debit.id, creditId: credit.id };
    });

    await expect(
      prisma.$transaction((tx) =>
        tx.ledgerEntry.createMany({
          data: [
            {
              transactionId: posted.journalId,
              ledgerAccountId: posted.debitId,
              direction: LedgerDirection.DEBIT,
              amount: "1.00",
            },
            {
              transactionId: posted.journalId,
              ledgerAccountId: posted.creditId,
              direction: LedgerDirection.CREDIT,
              amount: "1.00",
            },
          ],
        }),
      ),
    ).rejects.toBeDefined();
  });
});
