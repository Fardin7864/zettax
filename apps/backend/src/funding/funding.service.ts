import { HttpStatus, Injectable } from "@nestjs/common";
import {
  AccountMode,
  ActorType,
  DepositStatus,
  LedgerDirection,
  LedgerTransactionType,
  PaymentMethodType,
  Prisma,
  WithdrawalStatus,
} from "@prisma/client";
import {
  ComplianceService,
  type FeatureName,
} from "../compliance/compliance.service";
import { LedgerService, type LedgerLine } from "../database/ledger.service";
import { PrismaService } from "../database/prisma.service";
import { ControlService } from "../operations/control.service";
import { OutboxService } from "../database/outbox.service";
import type {
  CreateDepositDto,
  CreateWithdrawalDto,
  MarkWithdrawalPaidDto,
  UpdatePaymentMethodDto,
  UpdateConversionRatesDto,
} from "./funding.dto";
import {
  bdtFromWithdrawal,
  DEPOSIT_RATE_KEY,
  parseConversionRate,
  readConversionRates,
  usdFromDeposit,
  WITHDRAWAL_RATE_KEY,
} from "./conversion-rates";
import { fundingError } from "./funding.errors";
import {
  canReleaseWithdrawal,
  resolveWithdrawalTransition,
  type WithdrawalAction,
} from "./funding.state";
import {
  normalizeProviderTransactionId,
  parseBdt,
  parseUsd,
  validateBangladeshMobile,
} from "./funding.validation";

type AuditContext = {
  requestId: string;
  ipAddress?: string | undefined;
  userAgent?: string | undefined;
};

const fundingMethodTypes: PaymentMethodType[] = [
  PaymentMethodType.BKASH,
  PaymentMethodType.NAGAD,
  PaymentMethodType.ROCKET,
];

@Injectable()
export class FundingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly compliance: ComplianceService,
    private readonly ledger: LedgerService,
    private readonly controls: ControlService,
    private readonly outbox: OutboxService,
  ) {}

  listDeposits(userId: string) {
    return this.prisma.depositRequest.findMany({
      where: { userId },
      orderBy: { createdAt: "desc" },
      include: { paymentMethod: { select: { type: true, displayName: true } } },
    });
  }

  listWithdrawals(userId: string) {
    return this.prisma.withdrawalRequest.findMany({
      where: { userId },
      orderBy: { createdAt: "desc" },
      include: { paymentMethod: { select: { type: true, displayName: true } } },
    });
  }

  async listDepositsForReview(status?: DepositStatus, page = 1, pageSize = 25) {
    return this.prisma.$transaction(
      async (tx) => {
        const where = status ? { status } : {};
        const [rows, total] = await Promise.all([
          tx.depositRequest.findMany({
            where,
            skip: (page - 1) * pageSize,
            take: pageSize,
            orderBy: [{ createdAt: "desc" }, { id: "desc" }],
            include: {
              paymentMethod: { select: { type: true, displayName: true } },
              user: { select: { id: true, email: true, phone: true } },
            },
          }),
          tx.depositRequest.count({ where }),
        ]);
        return {
          items: rows.map((row) => ({
            ...row,
            virtualFunding: this.compliance.isVirtual,
          })),
          total,
          page,
          pageSize,
          totalPages: Math.max(1, Math.ceil(total / pageSize)),
        };
      },
      {
        isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead,
        timeout: 30_000,
        maxWait: 10_000,
      },
    );
  }

  async listWithdrawalsForReview(
    status?: WithdrawalStatus,
    page = 1,
    pageSize = 25,
  ) {
    return this.prisma.$transaction(
      async (tx) => {
        const where = status ? { status } : {};
        const [rows, total] = await Promise.all([
          tx.withdrawalRequest.findMany({
            where,
            skip: (page - 1) * pageSize,
            take: pageSize,
            orderBy: [{ createdAt: "desc" }, { id: "desc" }],
            include: {
              paymentMethod: { select: { type: true, displayName: true } },
              user: { select: { id: true, email: true, phone: true } },
            },
          }),
          tx.withdrawalRequest.count({ where }),
        ]);
        return {
          items: rows.map((row) => ({
            ...row,
            virtualFunding: this.compliance.isVirtual,
          })),
          total,
          page,
          pageSize,
          totalPages: Math.max(1, Math.ceil(total / pageSize)),
        };
      },
      {
        isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead,
        timeout: 30_000,
        maxWait: 10_000,
      },
    );
  }

  async listPaymentMethods(feature: "DEPOSITS" | "WITHDRAWALS") {
    const submissionsEnabled =
      this.compliance.isEnabled(feature) &&
      (this.compliance.isVirtual || (await this.controls.readiness()).ready);
    const [methods, rates] = await Promise.all([
      this.prisma.paymentMethod.findMany({
        where: { isEnabled: true, type: { in: fundingMethodTypes } },
        select: {
          id: true,
          type: true,
          displayName: true,
          accountNumber: true,
          accountType: true,
          instructions: true,
          minimumDeposit: true,
          maximumDeposit: true,
          feeType: true,
          feeValue: true,
        },
        orderBy: { displayName: "asc" },
      }),
      readConversionRates(this.prisma),
    ]);
    return {
      submissionsEnabled,
      virtualFunding: this.compliance.isVirtual,
      methods,
      depositBdtPerUsd: rates.depositBdtPerUsd.toFixed(4),
      withdrawalBdtPerUsd: rates.withdrawalBdtPerUsd.toFixed(4),
    };
  }

  async conversionRates() {
    const rates = await readConversionRates(this.prisma);
    return {
      depositBdtPerUsd: rates.depositBdtPerUsd.toFixed(4),
      withdrawalBdtPerUsd: rates.withdrawalBdtPerUsd.toFixed(4),
    };
  }

  async updateConversionRates(
    adminId: string,
    input: UpdateConversionRatesDto,
    audit: AuditContext,
  ) {
    const deposit = parseConversionRate(input.depositBdtPerUsd);
    const withdrawal = parseConversionRate(input.withdrawalBdtPerUsd);
    return this.prisma.$transaction(async (tx) => {
      const previous = await readConversionRates(tx);
      for (const [key, value] of [
        [DEPOSIT_RATE_KEY, deposit.toFixed(4)],
        [WITHDRAWAL_RATE_KEY, withdrawal.toFixed(4)],
      ] as const) {
        await tx.systemConfig.upsert({
          where: { key },
          create: { key, value, updatedBy: adminId },
          update: { value, updatedBy: adminId },
        });
      }
      await tx.auditLog.create({
        data: {
          actorType: ActorType.ADMIN,
          actorAdminId: adminId,
          action: "FUNDING_CONVERSION_RATES_UPDATED",
          resourceType: "SystemConfig",
          resourceId: "funding.conversionRates",
          requestId: audit.requestId,
          ipAddress: audit.ipAddress ?? null,
          userAgent: audit.userAgent ?? null,
          previousValue: {
            depositBdtPerUsd: previous.depositBdtPerUsd.toFixed(4),
            withdrawalBdtPerUsd: previous.withdrawalBdtPerUsd.toFixed(4),
          },
          newValue: {
            depositBdtPerUsd: deposit.toFixed(4),
            withdrawalBdtPerUsd: withdrawal.toFixed(4),
          },
        },
      });
      return {
        depositBdtPerUsd: deposit.toFixed(4),
        withdrawalBdtPerUsd: withdrawal.toFixed(4),
      };
    });
  }

  listPaymentMethodsForAdmin() {
    return this.prisma.paymentMethod.findMany({
      where: { type: { in: fundingMethodTypes } },
      orderBy: { displayName: "asc" },
    });
  }

  async updatePaymentMethod(
    id: string,
    adminId: string,
    input: UpdatePaymentMethodDto,
    audit: AuditContext,
  ) {
    const minimum = parseBdt(input.minimumDeposit);
    const maximum = parseBdt(input.maximumDeposit);
    if (minimum.greaterThan(maximum)) {
      fundingError(
        "PAYMENT_METHOD_LIMITS_INVALID",
        "Minimum deposit cannot be greater than maximum deposit",
      );
    }
    const instructions = input.instructions.trim();
    if (instructions.length < 10) {
      fundingError(
        "PAYMENT_METHOD_INSTRUCTIONS_REQUIRED",
        "Payment instructions must be clear and complete",
      );
    }

    return this.prisma.$transaction(async (tx) => {
      const previous = await tx.paymentMethod.findUnique({ where: { id } });
      if (!previous || !fundingMethodTypes.includes(previous.type)) {
        fundingError(
          "PAYMENT_METHOD_UNAVAILABLE",
          "Payment method is unavailable",
          HttpStatus.NOT_FOUND,
        );
      }
      const updated = await tx.paymentMethod.update({
        where: { id },
        data: {
          accountNumber: input.accountNumber,
          accountType: input.accountType,
          instructions,
          minimumDeposit: minimum,
          maximumDeposit: maximum,
          isEnabled: input.isEnabled,
        },
      });
      await this.audit(tx, {
        ...audit,
        actorType: ActorType.ADMIN,
        actorAdminId: adminId,
        action: "PAYMENT_METHOD_UPDATED",
        resourceType: "PaymentMethod",
        resourceId: id,
        previousValue: this.paymentMethodAuditValue(previous),
        newValue: this.paymentMethodAuditValue(updated),
      });
      return updated;
    });
  }

  async createDeposit(
    userId: string,
    idempotencyKey: string,
    input: CreateDepositDto,
    audit: AuditContext,
  ) {
    this.assertFeature("DEPOSITS");
    if (!this.compliance.isVirtual) await this.controls.requireReady();
    const amount = parseBdt(input.amount);
    const senderMobile = validateBangladeshMobile(input.senderMobile);
    const providerTransactionId = normalizeProviderTransactionId(
      input.providerTransactionId,
    );

    try {
      return await this.withSerializableRetry(async (tx) => {
        const existing = await tx.depositRequest.findUnique({
          where: { userId_idempotencyKey: { userId, idempotencyKey } },
        });
        if (existing) {
          if (
            existing.paymentMethodId !== input.paymentMethodId ||
            !existing.amount.equals(amount) ||
            existing.senderMobile !== senderMobile ||
            existing.providerTransactionId !== providerTransactionId ||
            existing.evidenceObjectKey !== input.evidenceObjectKey
          ) {
            fundingError(
              "IDEMPOTENCY_KEY_REUSED",
              "Idempotency key was already used for a different deposit",
              HttpStatus.CONFLICT,
            );
          }
          return existing;
        }

        const user = await tx.user.findUnique({
          where: { id: userId },
          select: {
            depositEnabled: true,
            accounts: {
              where: { mode: "REAL", status: "ACTIVE" },
              take: 1,
              select: { id: true },
            },
          },
        });
        if (!user)
          fundingError(
            "USER_NOT_FOUND",
            "User does not exist",
            HttpStatus.NOT_FOUND,
          );
        if (!user.depositEnabled) {
          fundingError(
            "DEPOSIT_DISABLED",
            "Deposits are disabled for this account",
            HttpStatus.FORBIDDEN,
          );
        }
        const account = user.accounts[0];
        if (!account) {
          fundingError(
            "REAL_ACCOUNT_REQUIRED",
            "An active real account is required",
            HttpStatus.CONFLICT,
          );
        }
        const method = await this.requirePaymentMethod(
          tx,
          input.paymentMethodId,
        );
        this.assertWithinLimits(
          amount,
          method.minimumDeposit,
          method.maximumDeposit,
        );
        const rate = (await readConversionRates(tx)).depositBdtPerUsd;
        if (input.expectedConversionRate !== undefined &&
            !parseConversionRate(input.expectedConversionRate).equals(rate)) {
          fundingError("CONVERSION_RATE_CHANGED", "Deposit rate changed. Refresh and review the new USD credit before retrying.", HttpStatus.CONFLICT);
        }
        const usdAmount = usdFromDeposit(amount, rate);

        const evidence = input.evidenceObjectKey
          ? await tx.evidenceFile.findUnique({
              where: { objectKey: input.evidenceObjectKey },
            })
          : null;
        if (
          input.evidenceObjectKey &&
          (!evidence ||
            evidence.ownerId !== userId ||
            evidence.ownerType !== "USER" ||
            evidence.purpose !== "DEPOSIT" ||
            evidence.status !== "CLEAN" ||
            evidence.claimedBy)
        )
          fundingError(
            "EVIDENCE_REQUIRED",
            "Upload a clean payment screenshot owned by this account.",
          );
        const deposit = await tx.depositRequest.create({
          data: {
            userId,
            accountId: account.id,
            paymentMethodId: method.id,
            idempotencyKey,
            amount,
            usdAmount,
            conversionRate: rate,
            senderMobile,
            providerTransactionId,
            evidenceObjectKey: input.evidenceObjectKey ?? null,
            status: DepositStatus.PENDING_REVIEW,
            receivingDetails: {
              accountNumber: method.accountNumber,
              accountType: method.accountType,
              type: method.type,
            },
          },
        });
        if (evidence)
          await tx.evidenceFile.update({
            where: { id: evidence.id },
            data: { claimedBy: `deposit:${deposit.id}` },
          });
        await this.audit(tx, {
          ...audit,
          actorType: ActorType.USER,
          actorUserId: userId,
          action: "DEPOSIT_REQUESTED",
          resourceType: "DepositRequest",
          resourceId: deposit.id,
          newValue: {
            amount: amount.toFixed(2),
            paymentMethodId: method.id,
            status: deposit.status,
          },
        });
        return deposit;
      });
    } catch (error: unknown) {
      this.rethrowDepositConstraint(error);
    }
  }

  async approveDeposit(
    depositId: string,
    adminId: string,
    audit: AuditContext,
  ) {
    return this.creditVerifiedDeposit(depositId, adminId, audit);
  }
  async verifyDeposit(
    id: string,
    adminId: string,
    reference: string,
    audit: AuditContext,
  ) {
    return this.withSerializableRetry(async (tx) => {
      await this.lockRow(tx, "deposit_requests", id);
      const deposit = await tx.depositRequest.findUnique({ where: { id } });
      if (!deposit || deposit.status !== "PENDING_REVIEW")
        fundingError(
          "DEPOSIT_INVALID_STATE",
          "Deposit is not pending review.",
          409,
        );
      const evidence = await tx.evidenceFile.findUnique({
        where: { objectKey: deposit.evidenceObjectKey ?? "" },
      });
      if (
        deposit.evidenceObjectKey &&
        evidence?.status !== "DELETED" &&
        (!evidence ||
          evidence.status !== "CLEAN" ||
          evidence.claimedBy !== `deposit:${id}`)
      )
        fundingError("EVIDENCE_REQUIRED", "Clean linked evidence is required.");
      if (deposit.verifiedBy) {
        if (
          deposit.verifiedBy === adminId &&
          deposit.verificationReference === reference
        )
          return deposit;
        fundingError(
          "DEPOSIT_ALREADY_VERIFIED",
          "Transfer verification is already recorded.",
          409,
        );
      }
      const updated = await tx.depositRequest.update({
        where: { id },
        data: {
          verifiedBy: adminId,
          verifiedAt: new Date(),
          verificationReference: reference,
        },
      });
      await this.audit(tx, {
        ...audit,
        actorType: "ADMIN",
        actorAdminId: adminId,
        action: "DEPOSIT_TRANSFER_VERIFIED",
        resourceType: "DepositRequest",
        resourceId: id,
        newValue: { reference },
      });
      return updated;
    });
  }
  private async creditVerifiedDeposit(
    depositId: string,
    adminId: string,
    audit: AuditContext,
  ) {
    this.assertFeature("DEPOSITS");
    return this.withSerializableRetry(async (tx) => {
      await this.lockRow(tx, "deposit_requests", depositId);
      const deposit = await tx.depositRequest.findUnique({
        where: { id: depositId },
      });
      if (!deposit)
        fundingError(
          "DEPOSIT_NOT_FOUND",
          "Deposit request was not found",
          HttpStatus.NOT_FOUND,
        );
      if (deposit.status === DepositStatus.CREDITED) return deposit;
      if (deposit.status !== DepositStatus.PENDING_REVIEW) {
        fundingError(
          "DEPOSIT_ALREADY_PROCESSED",
          "Deposit is not pending review",
          HttpStatus.CONFLICT,
        );
      }

      if (
        !this.compliance.isVirtual &&
        (!deposit.verifiedBy || deposit.verifiedBy === adminId)
      )
        fundingError(
          "INDEPENDENT_REVIEW_REQUIRED",
          "A different operator must first verify the actual provider transfer.",
          HttpStatus.FORBIDDEN,
        );
      const evidence = await tx.evidenceFile.findUnique({
        where: { objectKey: deposit.evidenceObjectKey ?? "" },
      });
      if (
        deposit.evidenceObjectKey &&
        evidence?.status !== "DELETED" &&
        (!evidence ||
          evidence.status !== "CLEAN" ||
          evidence.claimedBy !== `deposit:${deposit.id}`)
      )
        fundingError(
          "EVIDENCE_REQUIRED",
          "Evidence must remain clean and linked before credit.",
        );

      const accounts = await this.ensureLedgerAccounts(tx, deposit.accountId);
      const entries: LedgerLine[] = [
        {
          ledgerAccountId: accounts.cash,
          direction: LedgerDirection.DEBIT,
          amount: deposit.usdAmount,
        },
        {
          ledgerAccountId: accounts.available,
          direction: LedgerDirection.CREDIT,
          amount: deposit.usdAmount,
        },
      ];
      const ledger = await this.ledger.post(tx, {
        type: LedgerTransactionType.DEPOSIT,
        idempotencyKey: `deposit:${deposit.id}:credit`,
        reference: deposit.providerTransactionId,
        description: `Manual deposit credit ${deposit.id}`,
        entries,
      });
      await tx.wallet.upsert({
        where: {
          accountId_currencyCode: {
            accountId: deposit.accountId,
            currencyCode: "USD",
          },
        },
        create: {
          accountId: deposit.accountId,
          currencyCode: "USD",
          availableProjection: deposit.usdAmount,
        },
        update: { availableProjection: { increment: deposit.usdAmount } },
      });
      const updated = await tx.depositRequest.update({
        where: { id: deposit.id },
        data: {
          status: DepositStatus.CREDITED,
          statusVersion: { increment: 1 },
          reviewedBy: adminId,
          reviewedAt: new Date(),
          ledgerTransactionId: ledger.id,
        },
      });
      await this.audit(tx, {
        ...audit,
        actorType: ActorType.ADMIN,
        actorAdminId: adminId,
        action: "DEPOSIT_APPROVED_AND_CREDITED",
        resourceType: "DepositRequest",
        resourceId: deposit.id,
        previousValue: { status: deposit.status },
        newValue: { status: updated.status, ledgerTransactionId: ledger.id },
      });
      return updated;
    });
  }

  async rejectDeposit(
    depositId: string,
    adminId: string,
    reason: string,
    audit: AuditContext,
  ) {
    this.assertFeature("DEPOSITS");
    const rejectionReason = this.requireReason(reason);
    return this.withSerializableRetry(async (tx) => {
      await this.lockRow(tx, "deposit_requests", depositId);
      const deposit = await tx.depositRequest.findUnique({
        where: { id: depositId },
      });
      if (!deposit)
        fundingError(
          "DEPOSIT_NOT_FOUND",
          "Deposit request was not found",
          HttpStatus.NOT_FOUND,
        );
      if (deposit.status === DepositStatus.REJECTED) return deposit;
      if (deposit.status !== DepositStatus.PENDING_REVIEW) {
        fundingError(
          "DEPOSIT_ALREADY_PROCESSED",
          "Deposit is not pending review",
          HttpStatus.CONFLICT,
        );
      }
      const updated = await tx.depositRequest.update({
        where: { id: deposit.id },
        data: {
          status: DepositStatus.REJECTED,
          statusVersion: { increment: 1 },
          reviewedBy: adminId,
          reviewedAt: new Date(),
          rejectionReason,
        },
      });
      await this.audit(tx, {
        ...audit,
        actorType: ActorType.ADMIN,
        actorAdminId: adminId,
        action: "DEPOSIT_REJECTED",
        resourceType: "DepositRequest",
        resourceId: deposit.id,
        previousValue: { status: deposit.status },
        newValue: { status: updated.status, rejectionReason },
      });
      return updated;
    });
  }

  async createWithdrawal(
    userId: string,
    idempotencyKey: string,
    input: CreateWithdrawalDto,
    audit: AuditContext,
  ) {
    this.assertFeature("WITHDRAWALS");
    if (!this.compliance.isVirtual) await this.controls.requireReady();
    const usdAmount = parseUsd(input.amount);
    const receiverMobile = validateBangladeshMobile(input.receiverMobile);
    return this.withSerializableRetry(async (tx) => {
      const existing = await tx.withdrawalRequest.findUnique({
        where: { userId_idempotencyKey: { userId, idempotencyKey } },
      });
      if (existing) {
        if (
          existing.paymentMethodId !== input.paymentMethodId ||
          !existing.usdAmount.equals(usdAmount) ||
          existing.receiverMobile !== receiverMobile
        ) {
          fundingError(
            "IDEMPOTENCY_KEY_REUSED",
            "Idempotency key was already used for a different withdrawal",
            HttpStatus.CONFLICT,
          );
        }
        return existing;
      }

      const user = await tx.user.findUnique({
        where: { id: userId },
        select: {
          withdrawalEnabled: true,
          accounts: {
            where: { mode: "REAL", status: "ACTIVE" },
            take: 1,
            select: { id: true },
          },
        },
      });
      if (!user)
        fundingError(
          "USER_NOT_FOUND",
          "User does not exist",
          HttpStatus.NOT_FOUND,
        );
      if (!user.withdrawalEnabled) {
        fundingError(
          "WITHDRAWAL_DISABLED",
          "Withdrawals are disabled for this account",
          HttpStatus.FORBIDDEN,
        );
      }
      const account = user.accounts[0];
      if (!account) {
        fundingError(
          "REAL_ACCOUNT_REQUIRED",
          "An active real account is required",
          HttpStatus.CONFLICT,
        );
      }
      const approvedKyc = await tx.kycCase.findFirst({
        where: { userId, status: "APPROVED" },
        select: { id: true },
      });
      if (!approvedKyc && !this.compliance.isVirtual)
        fundingError(
          "KYC_REQUIRED",
          "Approved KYC is required for withdrawal",
          HttpStatus.FORBIDDEN,
        );

      const method = await this.requirePaymentMethod(tx, input.paymentMethodId);
      const rate = (await readConversionRates(tx)).withdrawalBdtPerUsd;
      if (input.expectedConversionRate !== undefined &&
          !parseConversionRate(input.expectedConversionRate).equals(rate)) {
        fundingError("CONVERSION_RATE_CHANGED", "Withdrawal rate changed. Refresh and review the new BDT payout before retrying.", HttpStatus.CONFLICT);
      }
      const amount = bdtFromWithdrawal(usdAmount, rate);
      this.assertWithinLimits(
        amount,
        method.minimumDeposit,
        method.maximumDeposit,
      );
      await this.ledger.lockWallet(tx, account.id);
      const wallet = await tx.wallet.findUnique({
        where: {
          accountId_currencyCode: {
            accountId: account.id,
            currencyCode: "USD",
          },
        },
      });
      if (!wallet || wallet.availableProjection.lessThan(usdAmount)) {
        fundingError(
          "INSUFFICIENT_FUNDS",
          "Available balance is insufficient",
          HttpStatus.CONFLICT,
        );
      }

      const accounts = await this.ensureLedgerAccounts(tx, account.id);
      const lockLedger = await this.ledger.post(tx, {
        type: LedgerTransactionType.WITHDRAWAL,
        idempotencyKey: `withdrawal:${userId}:${idempotencyKey}:lock`,
        description: "Withdrawal funds lock",
        entries: [
          {
            ledgerAccountId: accounts.available,
            direction: LedgerDirection.DEBIT,
            amount: usdAmount,
          },
          {
            ledgerAccountId: accounts.locked,
            direction: LedgerDirection.CREDIT,
            amount: usdAmount,
          },
        ],
      });
      const updatedWallet = await tx.wallet.updateMany({
        where: { id: wallet.id, availableProjection: { gte: usdAmount } },
        data: {
          availableProjection: { decrement: usdAmount },
          lockedProjection: { increment: usdAmount },
        },
      });
      if (updatedWallet.count !== 1) {
        fundingError(
          "INSUFFICIENT_FUNDS",
          "Available balance changed; retry withdrawal",
          HttpStatus.CONFLICT,
        );
      }
      const withdrawal = await tx.withdrawalRequest.create({
        data: {
          userId,
          accountId: account.id,
          paymentMethodId: method.id,
          idempotencyKey,
          amount,
          usdAmount,
          conversionRate: rate,
          receiverMobile,
          lockTransactionId: lockLedger.id,
        },
      });
      await this.audit(tx, {
        ...audit,
        actorType: ActorType.USER,
        actorUserId: userId,
        action: "WITHDRAWAL_REQUESTED_FUNDS_LOCKED",
        resourceType: "WithdrawalRequest",
        resourceId: withdrawal.id,
        newValue: {
          amountBdt: amount.toFixed(2),
          amountUsd: usdAmount.toFixed(2),
          status: withdrawal.status,
          lockTransactionId: lockLedger.id,
        },
      });
      return withdrawal;
    });
  }

  async transitionWithdrawal(
    withdrawalId: string,
    adminId: string,
    action: WithdrawalAction,
    audit: AuditContext,
  ) {
    this.assertFeature("WITHDRAWALS");
    return this.withSerializableRetry(async (tx) => {
      await this.lockRow(tx, "withdrawal_requests", withdrawalId);
      const withdrawal = await tx.withdrawalRequest.findUnique({
        where: { id: withdrawalId },
      });
      if (!withdrawal)
        fundingError(
          "WITHDRAWAL_NOT_FOUND",
          "Withdrawal request was not found",
          HttpStatus.NOT_FOUND,
        );
      const { next, replay } = resolveWithdrawalTransition(
        withdrawal.status,
        action,
      );
      if (replay) return withdrawal;
      if (
        action === "APPROVE" &&
        !this.compliance.isVirtual &&
        (!withdrawal.reviewStartedBy || withdrawal.reviewStartedBy === adminId)
      )
        fundingError(
          "INDEPENDENT_REVIEW_REQUIRED",
          "A different operator must approve the reviewed withdrawal.",
          HttpStatus.FORBIDDEN,
        );
      const updated = await tx.withdrawalRequest.update({
        where: { id: withdrawal.id },
        data: {
          status: next,
          statusVersion: { increment: 1 },
          reviewedBy: adminId,
          reviewedAt: new Date(),
          ...(action === "START_REVIEW"
            ? { reviewStartedBy: adminId }
            : action === "APPROVE"
              ? { approvedBy: adminId }
              : { processedBy: adminId }),
        },
      });
      await this.audit(tx, {
        ...audit,
        actorType: ActorType.ADMIN,
        actorAdminId: adminId,
        action: `WITHDRAWAL_${next}`,
        resourceType: "WithdrawalRequest",
        resourceId: withdrawal.id,
        previousValue: { status: withdrawal.status },
        newValue: { status: updated.status },
      });
      return updated;
    });
  }

  async rejectWithdrawal(
    withdrawalId: string,
    adminId: string,
    reason: string,
    audit: AuditContext,
  ) {
    this.assertFeature("WITHDRAWALS");
    const rejectionReason = this.requireReason(reason);
    return this.releaseWithdrawal(
      withdrawalId,
      { actorType: ActorType.ADMIN, actorAdminId: adminId },
      WithdrawalStatus.REJECTED,
      rejectionReason,
      audit,
    );
  }

  async cancelWithdrawal(
    withdrawalId: string,
    userId: string,
    audit: AuditContext,
  ) {
    this.assertFeature("WITHDRAWALS");
    return this.releaseWithdrawal(
      withdrawalId,
      { actorType: ActorType.USER, actorUserId: userId },
      WithdrawalStatus.CANCELLED,
      "Cancelled by user before review",
      audit,
      userId,
    );
  }

  completeVirtualWithdrawal(
    withdrawalId: string,
    adminId: string,
    audit: AuditContext,
  ) {
    return this.markWithdrawalPaid(
      withdrawalId,
      adminId,
      { providerTransactionId: `VIRTUAL${withdrawalId.replaceAll("-", "")}` },
      audit,
      true,
    );
  }

  async markWithdrawalPaid(
    withdrawalId: string,
    adminId: string,
    input: MarkWithdrawalPaidDto,
    audit: AuditContext,
    completeVirtual = false,
  ) {
    this.assertFeature("WITHDRAWALS");
    if (completeVirtual && !this.compliance.isVirtual)
      fundingError(
        "VIRTUAL_FUNDING_REQUIRED",
        "Direct completion is available only for virtual withdrawals.",
        HttpStatus.FORBIDDEN,
      );
    const providerTransactionId = normalizeProviderTransactionId(
      input.providerTransactionId,
    );
    try {
      return await this.withSerializableRetry(async (tx) => {
        await this.lockRow(tx, "withdrawal_requests", withdrawalId);
        const withdrawal = await tx.withdrawalRequest.findUnique({
          where: { id: withdrawalId },
        });
        if (!withdrawal)
          fundingError(
            "WITHDRAWAL_NOT_FOUND",
            "Withdrawal request was not found",
            HttpStatus.NOT_FOUND,
          );
        if (withdrawal.status === WithdrawalStatus.PAID) {
          if (
            !completeVirtual &&
            withdrawal.providerTransactionId !== providerTransactionId
          ) {
            fundingError(
              "WITHDRAWAL_ALREADY_PROCESSED",
              "Withdrawal was paid with different metadata",
              HttpStatus.CONFLICT,
            );
          }
          return withdrawal;
        }
        if (
          completeVirtual
            ? !(
                [
                  WithdrawalStatus.REQUESTED,
                  WithdrawalStatus.UNDER_REVIEW,
                  WithdrawalStatus.APPROVED,
                  WithdrawalStatus.PROCESSING,
                ] as WithdrawalStatus[]
              ).includes(withdrawal.status)
            : withdrawal.status !== WithdrawalStatus.PROCESSING
        ) {
          fundingError(
            "WITHDRAWAL_INVALID_STATE",
            "Withdrawal must be processing before it can be paid",
            HttpStatus.CONFLICT,
          );
        }
        if (
          !this.compliance.isVirtual &&
          (!withdrawal.approvedBy || withdrawal.approvedBy === adminId)
        )
          fundingError(
            "INDEPENDENT_REVIEW_REQUIRED",
            "The approver cannot confirm the payout.",
            HttpStatus.FORBIDDEN,
          );
        const evidence = await tx.evidenceFile.findUnique({
          where: { objectKey: input.evidenceObjectKey ?? "" },
        });
        if (
          !this.compliance.isVirtual &&
          (!evidence ||
            evidence.ownerId !== adminId ||
            evidence.ownerType !== "ADMIN" ||
            evidence.purpose !== "WITHDRAWAL" ||
            evidence.status !== "CLEAN" ||
            evidence.claimedBy)
        )
          fundingError(
            "EVIDENCE_REQUIRED",
            "Attach clean payout evidence owned by the paying operator.",
          );
        await this.ledger.lockWallet(tx, withdrawal.accountId);
        const accounts = await this.ensureLedgerAccounts(
          tx,
          withdrawal.accountId,
        );
        const settlement = await this.ledger.post(tx, {
          type: LedgerTransactionType.WITHDRAWAL,
          idempotencyKey: `withdrawal:${withdrawal.id}:settle`,
          reference: providerTransactionId,
          description: `Manual withdrawal settlement ${withdrawal.id}`,
          entries: [
            {
              ledgerAccountId: accounts.locked,
              direction: LedgerDirection.DEBIT,
              amount: withdrawal.usdAmount,
            },
            {
              ledgerAccountId: accounts.cash,
              direction: LedgerDirection.CREDIT,
              amount: withdrawal.usdAmount,
            },
          ],
        });
        const wallet = await tx.wallet.updateMany({
          where: {
            accountId: withdrawal.accountId,
            currencyCode: "USD",
            lockedProjection: { gte: withdrawal.usdAmount },
          },
          data: { lockedProjection: { decrement: withdrawal.usdAmount } },
        });
        if (wallet.count !== 1) {
          fundingError(
            "LEDGER_RECONCILIATION_FAILED",
            "Locked balance does not reconcile",
            HttpStatus.CONFLICT,
          );
        }
        const updated = await tx.withdrawalRequest.update({
          where: { id: withdrawal.id },
          data: {
            status: WithdrawalStatus.PAID,
            statusVersion: { increment: 1 },
            providerTransactionId,
            evidenceObjectKey: input.evidenceObjectKey ?? null,
            settlementTransactionId: settlement.id,
            ...(completeVirtual
              ? {
                  // Direct virtual completion is not an independent approval.
                  // Preserve any existing review trail; do not fabricate an
                  // approver equal to the reviewer (the database forbids it).
                  processedBy: adminId,
                }
              : {}),
            reviewedBy: adminId,
            reviewedAt: new Date(),
          },
        });
        if (evidence)
          await tx.evidenceFile.update({
            where: { id: evidence.id },
            data: { claimedBy: `withdrawal:${withdrawal.id}` },
          });
        await this.audit(tx, {
          ...audit,
          actorType: ActorType.ADMIN,
          actorAdminId: adminId,
          action: "WITHDRAWAL_PAID",
          resourceType: "WithdrawalRequest",
          resourceId: withdrawal.id,
          previousValue: { status: withdrawal.status },
          newValue: {
            status: updated.status,
            settlementTransactionId: settlement.id,
          },
        });
        return updated;
      });
    } catch (error: unknown) {
      if (this.isUniqueConstraint(error)) {
        fundingError(
          "PROVIDER_TRANSACTION_ID_DUPLICATE",
          "Provider transaction ID has already been recorded",
          HttpStatus.CONFLICT,
        );
      }
      throw error;
    }
  }

  private async releaseWithdrawal(
    withdrawalId: string,
    actor: {
      actorType: ActorType;
      actorAdminId?: string;
      actorUserId?: string;
    },
    nextStatus: "REJECTED" | "CANCELLED",
    reason: string,
    audit: AuditContext,
    ownerUserId?: string,
  ) {
    return this.withSerializableRetry(async (tx) => {
      await this.lockRow(tx, "withdrawal_requests", withdrawalId);
      const withdrawal = await tx.withdrawalRequest.findUnique({
        where: { id: withdrawalId },
      });
      if (!withdrawal || (ownerUserId && withdrawal.userId !== ownerUserId)) {
        fundingError(
          "WITHDRAWAL_NOT_FOUND",
          "Withdrawal request was not found",
          HttpStatus.NOT_FOUND,
        );
      }
      if (withdrawal.status === nextStatus) return withdrawal;
      const allowed = canReleaseWithdrawal(
        withdrawal.status,
        Boolean(ownerUserId),
      );
      if (!allowed) {
        fundingError(
          "WITHDRAWAL_INVALID_STATE",
          "Funds cannot be released after processing has started",
          HttpStatus.CONFLICT,
        );
      }
      await this.ledger.lockWallet(tx, withdrawal.accountId);
      const lockLedger = await tx.ledgerTransaction.findUnique({
        where: { id: withdrawal.lockTransactionId },
        include: { entries: true },
      });
      if (!lockLedger) {
        fundingError(
          "LEDGER_RECONCILIATION_FAILED",
          "Withdrawal lock transaction is missing",
          HttpStatus.CONFLICT,
        );
      }
      const reversalEntries = lockLedger.entries.map((entry) => ({
        ledgerAccountId: entry.ledgerAccountId,
        direction:
          entry.direction === LedgerDirection.DEBIT
            ? LedgerDirection.CREDIT
            : LedgerDirection.DEBIT,
        amount: entry.amount,
      }));
      const reversal = await this.ledger.post(tx, {
        type: LedgerTransactionType.REVERSAL,
        idempotencyKey: `withdrawal:${withdrawal.id}:release`,
        reversalOfId: lockLedger.id,
        description: `Release withdrawal lock ${withdrawal.id}`,
        entries: reversalEntries,
      });
      const wallet = await tx.wallet.updateMany({
        where: {
          accountId: withdrawal.accountId,
          currencyCode: "USD",
          lockedProjection: { gte: withdrawal.usdAmount },
        },
        data: {
          availableProjection: { increment: withdrawal.usdAmount },
          lockedProjection: { decrement: withdrawal.usdAmount },
        },
      });
      if (wallet.count !== 1) {
        fundingError(
          "LEDGER_RECONCILIATION_FAILED",
          "Locked balance does not reconcile",
          HttpStatus.CONFLICT,
        );
      }
      const updated = await tx.withdrawalRequest.update({
        where: { id: withdrawal.id },
        data: {
          status: nextStatus,
          statusVersion: { increment: 1 },
          rejectionReason: reason,
          reviewedBy: actor.actorAdminId ?? null,
          reviewedAt: new Date(),
          settlementTransactionId: reversal.id,
        },
      });
      await this.audit(tx, {
        ...audit,
        ...actor,
        action: `WITHDRAWAL_${nextStatus}_FUNDS_RELEASED`,
        resourceType: "WithdrawalRequest",
        resourceId: withdrawal.id,
        previousValue: { status: withdrawal.status },
        newValue: {
          status: updated.status,
          reversalTransactionId: reversal.id,
        },
      });
      return updated;
    });
  }

  private async withSerializableRetry<T>(
    work: (tx: Prisma.TransactionClient) => Promise<T>,
  ): Promise<T> {
    for (let attempt = 1; attempt <= 3; attempt += 1) {
      try {
        return await this.prisma.$transaction(work, {
          isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
          // Hosted Supabase round trips can exceed Prisma's 5-second default.
          timeout: 30_000,
          maxWait: 10_000,
        });
      } catch (error) {
        if (
          error instanceof Prisma.PrismaClientKnownRequestError &&
          error.code === "P2028"
        ) {
          fundingError(
            "FUNDING_TRANSACTION_TIMEOUT",
            "The funding request timed out. Retry the original request; do not submit a new one.",
            HttpStatus.SERVICE_UNAVAILABLE,
          );
        }
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

  private assertFeature(feature: FeatureName): void {
    if (!this.compliance.isEnabled(feature)) {
      fundingError(
        feature === "DEPOSITS" ? "DEPOSIT_DISABLED" : "WITHDRAWAL_DISABLED",
        `${feature === "DEPOSITS" ? "Deposits" : "Withdrawals"} require server-side production approval`,
        HttpStatus.FORBIDDEN,
      );
    }
  }

  private async requirePaymentMethod(tx: Prisma.TransactionClient, id: string) {
    const method = await tx.paymentMethod.findUnique({ where: { id } });
    if (
      !method ||
      !method.isEnabled ||
      !fundingMethodTypes.includes(method.type)
    ) {
      fundingError(
        "PAYMENT_METHOD_UNAVAILABLE",
        "Payment method is unavailable",
        HttpStatus.NOT_FOUND,
      );
    }
    return method;
  }

  private assertWithinLimits(
    amount: Prisma.Decimal,
    minimum: Prisma.Decimal,
    maximum: Prisma.Decimal,
  ): void {
    if (
      amount.lessThan(minimum) ||
      (!this.compliance.isVirtual && amount.greaterThan(maximum))
    ) {
      fundingError(
        "AMOUNT_OUTSIDE_LIMITS",
        this.compliance.isVirtual
          ? `Amount must be at least ${minimum.toFixed(2)} virtual BDT`
          : `Amount must be between ${minimum.toFixed(2)} and ${maximum.toFixed(2)} BDT`,
      );
    }
  }

  private requireReason(reason: string): string {
    const value = reason.trim();
    if (value.length < 3)
      fundingError("REASON_REQUIRED", "A meaningful reason is required");
    return value;
  }

  private async ensureLedgerAccounts(
    tx: Prisma.TransactionClient,
    accountId: string,
  ) {
    const accounts = await this.ledger.ensureAccountLedgerAccounts(
      tx,
      accountId,
      AccountMode.REAL,
    );
    return {
      cash: accounts.control,
      available: accounts.available,
      locked: accounts.locked,
    };
  }

  private async lockRow(
    tx: Prisma.TransactionClient,
    table: "deposit_requests" | "withdrawal_requests",
    id: string,
  ): Promise<void> {
    if (table === "deposit_requests") {
      await tx.$queryRaw`SELECT id FROM deposit_requests WHERE id = ${id}::uuid FOR UPDATE`;
    } else {
      await tx.$queryRaw`SELECT id FROM withdrawal_requests WHERE id = ${id}::uuid FOR UPDATE`;
    }
  }

  private async audit(
    tx: Prisma.TransactionClient,
    input: AuditContext & {
      actorType: ActorType;
      actorUserId?: string;
      actorAdminId?: string;
      action: string;
      resourceType: string;
      resourceId: string;
      previousValue?: Prisma.InputJsonValue;
      newValue?: Prisma.InputJsonValue;
    },
  ): Promise<void> {
    const data: Prisma.AuditLogUncheckedCreateInput = {
      actorType: input.actorType,
      actorUserId: input.actorUserId ?? null,
      actorAdminId: input.actorAdminId ?? null,
      action: input.action,
      resourceType: input.resourceType,
      resourceId: input.resourceId,
      ...(input.previousValue === undefined
        ? {}
        : { previousValue: input.previousValue }),
      ...(input.newValue === undefined ? {} : { newValue: input.newValue }),
      ipAddress: input.ipAddress ?? null,
      userAgent: input.userAgent ?? null,
      requestId: input.requestId,
    };
    await tx.auditLog.create({
      data,
    });
    const funding =
      input.resourceType === "DepositRequest"
        ? await tx.depositRequest.findUnique({
            where: { id: input.resourceId },
          })
        : input.resourceType === "WithdrawalRequest"
          ? await tx.withdrawalRequest.findUnique({
              where: { id: input.resourceId },
            })
          : null;
    if (funding)
      await this.outbox.enqueueAccount(tx, funding.userId, {
        aggregateType: "Account",
        aggregateId: funding.accountId,
        eventType: "FUNDING_UPDATED",
        payload: {
          accountId: funding.accountId,
          mode: "REAL",
          fundingId: funding.id,
          type: input.resourceType,
          amount: funding.usdAmount.toFixed(2),
          currency: "USD",
          amountBdt: funding.amount.toFixed(2),
          conversionRateBdtPerUsd: funding.conversionRate.toFixed(4),
          status: funding.status,
        },
      });
  }

  private paymentMethodAuditValue(method: {
    type: PaymentMethodType;
    displayName: string;
    accountNumber: string;
    accountType: string;
    instructions: string;
    minimumDeposit: Prisma.Decimal;
    maximumDeposit: Prisma.Decimal;
    isEnabled: boolean;
  }): Prisma.InputJsonValue {
    return {
      type: method.type,
      displayName: method.displayName,
      accountNumber: method.accountNumber,
      accountType: method.accountType,
      instructions: method.instructions,
      minimumDeposit: method.minimumDeposit.toFixed(2),
      maximumDeposit: method.maximumDeposit.toFixed(2),
      isEnabled: method.isEnabled,
    };
  }

  private rethrowDepositConstraint(error: unknown): never {
    if (this.isUniqueConstraint(error)) {
      fundingError(
        "PROVIDER_TRANSACTION_ID_DUPLICATE",
        "Provider transaction ID has already been submitted",
        HttpStatus.CONFLICT,
      );
    }
    throw error;
  }

  private isUniqueConstraint(error: unknown): boolean {
    return (
      error instanceof Prisma.PrismaClientKnownRequestError &&
      error.code === "P2002"
    );
  }
}
