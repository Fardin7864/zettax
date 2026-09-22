// Exercise the real database constraints, then roll back EVERY probe write.
// No withdrawal is actually completed and no notification is delivered.
import { readFileSync } from "node:fs";
import { ConfigService } from "@nestjs/config";
import { Prisma } from "@prisma/client";
import { PrismaService } from "../src/database/prisma.service";
import { LedgerService } from "../src/database/ledger.service";
import { OutboxService } from "../src/database/outbox.service";
import { ComplianceService } from "../src/compliance/compliance.service";
import { FundingService } from "../src/funding/funding.service";

async function main() {
  const input: Record<string, string> = {};
  for (const line of readFileSync("../../.env.local", "utf8").split(/\r?\n/)) {
    const match = /^([^#=]+)=(.*)$/.exec(line);
    if (match)
      input[match[1]!.trim()] = match[2]!
        .trim()
        .replace(/^(["'])(.*)\1$/, "$2");
  }
  process.env.DATABASE_URL = input.DATABASE_URL;
  const compliance = new ComplianceService(new ConfigService(input));
  if (!compliance.isVirtual)
    throw new Error("Probe is limited to virtual funding.");
  const prisma = new PrismaService();
  try {
    const request = await prisma.withdrawalRequest.findFirst({
      where: {
        status: { in: ["REQUESTED", "UNDER_REVIEW", "APPROVED", "PROCESSING"] },
      },
      orderBy: { createdAt: "desc" },
    });
    const admin = await prisma.adminUser.findFirst({
      where: { active: true },
      select: { id: true },
    });
    if (!request || !admin) {
      console.log(
        "No active virtual withdrawal available for rollback verification.",
      );
      return;
    }
    let proof: Record<string, boolean> | undefined;
    try {
      await prisma.$transaction(
        async (tx) => {
          const facade = {
            $transaction: (
              work: (tx: Prisma.TransactionClient) => Promise<unknown>,
            ) => work(tx),
            withdrawalRequest: tx.withdrawalRequest,
          } as unknown as PrismaService;
          const service = new FundingService(
            facade,
            compliance,
            new LedgerService(),
            {} as never,
            new OutboxService(),
          );
          const before = await tx.wallet.findUniqueOrThrow({
            where: {
              accountId_currencyCode: {
                accountId: request.accountId,
                currencyCode: "BDT",
              },
            },
          });
          const eventCount = await tx.accountEvent.count({
            where: { userId: request.userId },
          });
          const result = await service.completeVirtualWithdrawal(
            request.id,
            admin.id,
            { requestId: "rollback-verification" },
          );
          const replay = await service.completeVirtualWithdrawal(
            request.id,
            admin.id,
            { requestId: "rollback-verification" },
          );
          const after = await tx.wallet.findUniqueOrThrow({
            where: { id: before.id },
          });
          const userHistory = await service.listWithdrawals(request.userId);
          const adminHistory = await service.listWithdrawalsForReview(
            "PAID",
            1,
            100,
          );
          proof = {
            databaseConstraintPassed: result.status === "PAID",
            availableBalanceUnchanged: after.availableProjection.equals(
              before.availableProjection,
            ),
            lockedAmountSettledOnce: after.lockedProjection.equals(
              before.lockedProjection.minus(request.amount),
            ),
            replayUsesSameSettlement:
              result.settlementTransactionId === replay.settlementTransactionId,
            userHistoryUpdated: userHistory.some(
              (row) => row.id === request.id && row.status === "PAID",
            ),
            adminHistoryUpdated: adminHistory.items.some(
              (row) => row.id === request.id && row.status === "PAID",
            ),
            exactlyOneRealtimeEvent:
              (await tx.accountEvent.count({
                where: { userId: request.userId },
              })) ===
              eventCount + 1,
          };
          if (Object.values(proof).some((value) => !value))
            throw new Error("Probe assertions failed.");
          throw new Error("ROLLBACK_VERIFIED_PROBE");
        },
        {
          isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
          timeout: 60_000,
          maxWait: 10_000,
        },
      );
    } catch (error) {
      if (
        !(error instanceof Error) ||
        error.message !== "ROLLBACK_VERIFIED_PROBE"
      )
        throw new Error("Live rollback verification failed.");
    }
    const unchanged = await prisma.withdrawalRequest.findUniqueOrThrow({
      where: { id: request.id },
    });
    if (
      unchanged.status !== request.status ||
      unchanged.settlementTransactionId !== request.settlementTransactionId
    )
      throw new Error("Probe rollback check failed.");
    console.log({ ...proof, allProbeWritesRolledBack: true });
  } finally {
    await prisma.$disconnect();
  }
}
void main().catch(() => {
  console.error("Virtual withdrawal rollback verification failed.");
  process.exitCode = 1;
});
