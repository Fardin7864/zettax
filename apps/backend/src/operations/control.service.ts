import { Injectable, Module } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { Prisma } from "@prisma/client";
import { PrismaService } from "../database/prisma.service";
import { ApiErrorException } from "../http/api-error";

export const RELEASE_GATES = [
  "ENGINEERING",
  "SECURITY",
  "COMPLIANCE",
  "LEGAL",
  "CUSTODY",
  "PAYMENT_PROVIDER",
  "RECONCILIATION",
  "OPERATIONS",
  "TREASURY",
  "EXECUTIVE",
  "COUNTERPARTY_RISK",
] as const;
@Injectable()
export class ControlService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}
  version() {
    return this.config.get<string>("RELEASE_VERSION", "local-unapproved");
  }
  async treasury() {
    const statements = await this.prisma.treasuryStatement.findMany({
      where: { status: "APPROVED" },
      orderBy: [{ asOf: "desc" }, { createdAt: "desc" }],
    });
    const latest = new Map<string, (typeof statements)[number]>();
    for (const row of statements)
      if (!latest.has(row.accountReference))
        latest.set(row.accountReference, row);
    let customer = new Prisma.Decimal(0),
      reserve = new Prisma.Decimal(0),
      stale = 0;
    const cleanEvidence = await this.prisma.evidenceFile.findMany({
      where: {
        id: { in: [...latest.values()].map((row) => row.evidenceId) },
        status: "CLEAN",
      },
    });
    for (const row of latest.values()) {
      if (
        Date.now() - row.asOf.getTime() > 86400000 ||
        !cleanEvidence.some(
          (e) =>
            e.id === row.evidenceId && e.claimedBy === `treasury:${row.id}`,
        )
      ) {
        stale++;
        continue;
      }
      if (row.category === "CUSTOMER") customer = customer.plus(row.balance);
      else reserve = reserve.plus(row.balance);
    }
    const wallets = await this.prisma.wallet.aggregate({
      where: { account: { mode: "REAL" } },
      _sum: { availableProjection: true, lockedProjection: true },
    });
    const liabilities = (
      wallets._sum.availableProjection ?? new Prisma.Decimal(0)
    ).plus(wallets._sum.lockedProjection ?? 0);
    const contracts = await this.prisma.timedContract.aggregate({
      where: { account: { mode: "REAL" }, result: "PENDING" },
      _sum: { investmentAmount: true },
      _count: true,
    });
    const predictions = await this.prisma.predictionPosition.aggregate({
      where: { mode: "REAL", result: "PENDING" },
      _sum: { stake: true },
      _count: true,
    });
    return {
      customerAssets: customer.toFixed(2),
      reserveAssets: reserve.toFixed(2),
      customerLiabilities: liabilities.toFixed(2),
      customerCoverageGap: Prisma.Decimal.max(
        0,
        liabilities.minus(customer),
      ).toFixed(2),
      openContractStake: (
        contracts._sum.investmentAmount ?? new Prisma.Decimal(0)
      ).toFixed(2),
      openContractCount: contracts._count,
      openPredictionStake: (
        predictions._sum.stake ?? new Prisma.Decimal(0)
      ).toFixed(2),
      openPredictionCount: predictions._count,
      staleAccounts: stale,
      covered:
        customer.greaterThanOrEqualTo(liabilities) &&
        reserve.greaterThan(0) &&
        stale === 0,
      notice:
        "Verified statements are point-in-time evidence, not a bank feed. An uncapped BUY return has unbounded future exposure; a finite reserve does not guarantee every future payout.",
    };
  }
  async readiness() {
    const version = this.version();
    const recorded = await this.prisma.releaseApproval.findMany({
      where: { version, revokedAt: null, expiresAt: { gt: new Date() } },
    });
    const authorities = await this.prisma.adminUser.findMany({
      where: { id: { in: recorded.map((a) => a.approvedBy) }, active: true },
      include: {
        assignments: {
          include: {
            role: {
              include: { permissions: { include: { permission: true } } },
            },
          },
        },
      },
    });
    const evidence = await this.prisma.evidenceFile.findMany({
      where: {
        id: {
          in: recorded
            .map((a) => a.evidenceReference)
            .filter((ref) => !ref.startsWith("office:")),
        },
        status: "CLEAN",
      },
    });
    const approvals = recorded.filter(
      (a) =>
        ((["LEGAL", "COMPLIANCE"].includes(a.gate) &&
          a.evidenceReference.startsWith("office:") &&
          a.evidenceReference.length >= 26) ||
          evidence.some(
            (e) =>
              e.id === a.evidenceReference && e.claimedBy === `release:${a.id}`,
          )) &&
        authorities.some(
          (admin) =>
            admin.id === a.approvedBy &&
            admin.assignments.some((role) =>
              role.role.permissions.some(
                (p) => p.permission.key === `release.${a.gate.toLowerCase()}`,
              ),
            ),
        ),
    );
    const reconciliation = await this.reconcile();
    const missing = RELEASE_GATES.filter(
      (gate) => !approvals.some((a) => a.gate === gate),
    );
    const treasury = await this.treasury();
    const signers = new Set(approvals.map((a) => a.approvedBy)).size;
    return {
      version,
      approvals,
      missing,
      treasury,
      reconciliation,
      independentSigners: signers,
      ready:
        missing.length === 0 &&
        signers >= 5 &&
        treasury.covered &&
        reconciliation.clean &&
        version !== "local-unapproved",
    };
  }
  async reconcile() {
    const breaks = await this.prisma.$queryRaw<Array<{ count: bigint }>>`
      WITH balances AS (
        SELECT la.account_id,la.currency_code,
        COALESCE(SUM(CASE WHEN la.code LIKE '%:AVAILABLE:%' THEN CASE WHEN le.direction='CREDIT' THEN le.amount ELSE -le.amount END ELSE 0 END),0) AS available,
        COALESCE(SUM(CASE WHEN la.code LIKE '%:LOCKED:%' THEN CASE WHEN le.direction='CREDIT' THEN le.amount ELSE -le.amount END ELSE 0 END),0) AS locked
        FROM ledger_accounts la LEFT JOIN ledger_entries le ON le.ledger_account_id=la.id
        WHERE la.mode='REAL' AND la.account_id IS NOT NULL GROUP BY la.account_id,la.currency_code
      ) SELECT COUNT(*) AS count FROM wallets w JOIN accounts a ON a.id=w.account_id
      LEFT JOIN balances b ON b.account_id=w.account_id AND b.currency_code=w.currency_code
      WHERE a.mode='REAL' AND (w.available_projection<>COALESCE(b.available,0) OR w.locked_projection<>COALESCE(b.locked,0) OR w.available_projection<0 OR w.locked_projection<0)
    `;
    return {
      clean: breaks[0]?.count === 0n,
      walletBreaks: Number(breaks[0]?.count ?? 0n),
    };
  }
  async requireReady() {
    const state = await this.readiness();
    if (!state.ready)
      throw new ApiErrorException(
        "RELEASE_NOT_APPROVED",
        "Release approvals and verified treasury coverage are required.",
        403,
      );
  }
}
@Module({ providers: [ControlService], exports: [ControlService] })
export class ControlModule {}
