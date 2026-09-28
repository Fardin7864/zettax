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
  creator: {
    select: { profile: { select: { fullName: true, avatarObjectKey: true } } },
  },
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
      minimumStake: "0.01",
      maximumStake: "100000.00",
      minimumExpiryMinutes: 10,
      maximumExpiryDays: 30,
      missingPriceRefundHours: 24,
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
      creatorId: row.creatorId,
      generationContext: row.generationContext,
      nextSettlementAt: row.nextSettlementAt,
      lastSettlementError: row.lastSettlementError,
      creatorAvatarUrl:
        row.creatorId && row.creator?.profile?.avatarObjectKey
          ? `/community/users/${row.creatorId}/avatar`
          : null,
      participantCount: row.participantCount,
      cancellationReason: row.cancellationReason,
      cancelledAt: row.cancelledAt,
      settlementTimestamp: row.settlementTimestamp,
      displayStatus:
        row.status === "OPEN" && row.expiresAt.getTime() <= Date.now()
          ? "CLOSED"
          : row.status,
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

  async list(query: PredictionQuestionsQueryDto, creatorId?: string) {
    const where: Prisma.PredictionQuestionWhereInput = {
      ...(creatorId
        ? { creatorId }
        : query.source === "PLATFORM"
          ? { creatorId: null }
          : query.source === "MEMBERS"
            ? { creatorId: { not: null } }
            : {}),
      ...(query.status === "OPEN"
        ? { status: "OPEN", expiresAt: { gt: new Date() } }
        : query.status === "CLOSED"
          ? { status: "OPEN", expiresAt: { lte: new Date() } }
          : query.status
            ? { status: query.status }
            : {}),
      ...(query.search
        ? {
            instrument: {
              OR: [
                { symbol: { contains: query.search, mode: "insensitive" } },
                { name: { contains: query.search, mode: "insensitive" } },
              ],
            },
          }
        : {}),
    };
    const rows = await this.prisma.predictionQuestion.findMany({
      where,
      include: questionInclude,
      orderBy:
        query.sort === "ENDING"
          ? [{ expiresAt: "asc" }, { id: "asc" }]
          : query.sort === "POPULAR"
            ? [
                { participantCount: "desc" },
                { createdAt: "desc" },
                { id: "desc" },
              ]
            : [{ createdAt: "desc" }, { id: "desc" }],
      ...(query.cursor ? { cursor: { id: query.cursor }, skip: 1 } : {}),
      take: 21,
    });
    const items = rows.slice(0, 20).map((row) => this.question(row));
    return {
      items,
      nextCursor: rows.length > 20 ? items.at(-1)?.id : null,
      serverTime: new Date().toISOString(),
    };
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

  async create(
    creatorId: string | null,
    body: CreatePredictionQuestionDto,
    requestKey?: string,
    generated?: { key: string; context: Prisma.InputJsonObject },
  ) {
    if (creatorId && requestKey) {
      const prior = await this.prisma.predictionQuestion.findUnique({
        where: {
          creatorId_clientRequestKey: {
            creatorId,
            clientRequestKey: requestKey,
          },
        },
        include: questionInclude,
      });
      if (prior) {
        if (
          prior.condition !== body.condition ||
          !prior.targetPrice.equals(body.targetPrice) ||
          prior.instrument.slug !== body.instrumentId ||
          prior.expiresAt.toISOString() !==
            new Date(body.expiresAt).toISOString()
        )
          this.error(
            "IDEMPOTENCY_KEY_REUSED",
            "Request key was used for another question.",
            409,
          );
        return this.question(prior);
      }
    }
    if (creatorId) {
      const user = await this.prisma.user.findUnique({
        where: { id: creatorId },
        select: { loginEnabled: true, predictionCreationEnabled: true },
      });
      if (!user?.loginEnabled || !user.predictionCreationEnabled)
        this.error(
          "CREATION_RESTRICTED",
          "Prediction creation is restricted for this account.",
          403,
        );
    }
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
    const created = await this.serializable<QuestionRow>(async (tx) => {
      if (generated) {
        const existing = await tx.predictionQuestion.findUnique({
          where: { systemTemplateKey: generated.key },
          include: questionInclude,
        });
        if (existing) return existing;
      }
      if (creatorId) {
        await tx.$queryRaw`SELECT id FROM users WHERE id = ${creatorId}::uuid FOR UPDATE`;
        const user = await tx.user.findUnique({
          where: { id: creatorId },
          select: { predictionCreationEnabled: true, loginEnabled: true },
        });
        if (!user?.predictionCreationEnabled || !user.loginEnabled)
          this.error(
            "CREATION_RESTRICTED",
            "Prediction creation is restricted.",
            403,
          );
        if (requestKey) {
          const prior = await tx.predictionQuestion.findUnique({
            where: {
              creatorId_clientRequestKey: {
                creatorId,
                clientRequestKey: requestKey,
              },
            },
            include: questionInclude,
          });
          if (prior) {
            if (
              prior.instrumentId !== instrument.id ||
              prior.condition !== body.condition ||
              !prior.targetPrice.equals(target) ||
              prior.expiresAt.getTime() !== expiry.getTime()
            )
              this.error(
                "IDEMPOTENCY_CONFLICT",
                "This request key was already used for different prediction terms.",
                409,
              );
            return prior;
          }
        }
        const active = await tx.predictionQuestion.count({
          where: { creatorId, status: "OPEN" },
        });
        if (active >= 5)
          this.error(
            "QUESTION_LIMIT",
            "You can have up to five open questions.",
            429,
          );
      }
      return tx.predictionQuestion.create({
        data: {
          creatorId,
          clientRequestKey: requestKey ?? null,
          ...(generated
            ? {
                systemTemplateKey: generated.key,
                generationContext: generated.context,
              }
            : {}),
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
    });
    this.gateway.created(created.id);
    return this.question(created);
  }

  /** Real archived price anchors, never fabricated forecasts or retroactive bets. */
  async ensurePlatformQuestions() {
    const now = new Date();
    let created = 0;
    const templates = [
      {
        name: "NEXT_HOUR",
        lookbackHours: 0,
        horizonHours: 1,
        condition: "ABOVE" as const,
      },
      {
        name: "HOURLY_RECLAIM",
        lookbackHours: 1,
        horizonHours: 4,
        condition: "ABOVE" as const,
      },
      {
        name: "DAILY_LEVEL",
        lookbackHours: 24,
        horizonHours: 24,
        condition: "BELOW" as const,
      },
    ];
    for (const slug of [
      "btc-usd",
      "eth-usd",
      "sol-usd",
      "xrp-usd",
      "bch-usd",
      "ada-usd",
      "doge-usd",
      "avax-usd",
      "link-usd",
      "ltc-usd",
      "dot-usd",
      "sui-usd",
    ]) {
      const instrument = await this.prisma.instrument.findUnique({
        where: { slug },
      });
      if (!instrument?.demoEnabled || instrument.assetClass !== "CRYPTO")
        continue;
      for (const template of templates) {
        // One active question per market/template, across repeated worker cycles.
        const prefix = `${slug}:${template.name}:`;
        const existing = await this.prisma.predictionQuestion.count({
          where: {
            systemTemplateKey: { startsWith: prefix },
            status: "OPEN",
            expiresAt: { gt: now },
          },
        });
        if (existing) continue;
        const bucket = Math.floor(now.getTime() / 3_600_000);
        const key = `${prefix}${bucket}`;
        // A cancellation must not immediately recreate the same question.
        if (
          await this.prisma.predictionQuestion.findUnique({
            where: { systemTemplateKey: key },
          })
        )
          continue;
        try {
          const historical = await this.prices.at(
            instrument,
            new Date(now.getTime() - template.lookbackHours * 3_600_000),
          );
          await this.create(
            null,
            {
              instrumentId: slug,
              condition: template.condition,
              targetPrice: historical.price.toFixed(instrument.pricePrecision),
              expiresAt: new Date(
                (bucket + template.horizonHours + 1) * 3_600_000,
              ).toISOString(),
            },
            undefined,
            {
              key,
              context: {
                kind: "HISTORICAL_PRICE_ANCHOR",
                template: template.name,
                lookbackHours: template.lookbackHours,
                anchorPrice: historical.price.toFixed(),
                anchorTimestamp: historical.timestamp.toISOString(),
                source: historical.providerId,
                generatedAt: now.toISOString(),
                explanation:
                  template.lookbackHours === 0
                    ? "Compare the future price with the verified price at creation."
                    : `Compare the future price with the verified price ${template.lookbackHours} hours before creation.`,
              },
            },
          );
          created++;
        } catch (error) {
          Logger.warn(
            `Platform question ${slug}/${template.name} skipped: ${error instanceof Error ? error.name : "UnknownError"}`,
            "PredictionQuestions",
          );
        }
      }
    }
    return { created };
  }

  async myPositions(
    userId: string,
    query: PredictionQuestionsQueryDto = {},
    questionId?: string,
  ) {
    const rows = await this.prisma.predictionPosition.findMany({
      where: { userId, ...(questionId ? { questionId } : {}) },
      include: { question: { include: questionInclude } },
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      ...(query.cursor ? { cursor: { id: query.cursor }, skip: 1 } : {}),
      take: 21,
    });
    const items = rows.slice(0, 20).map((row) => ({
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
    return { items, nextCursor: rows.length > 20 ? items.at(-1)?.id : null };
  }

  async personalEvents(userId: string, afterSequence?: string) {
    if (
      afterSequence !== undefined &&
      (!/^\d{1,19}$/.test(afterSequence) ||
        BigInt(afterSequence) > 9223372036854775807n)
    )
      this.error("SEQUENCE_INVALID", "Invalid event sequence.", 400);
    const stream = await this.prisma.accountEventStream.findUnique({
      where: { userId },
      select: { lastSequence: true },
    });
    const latest = stream?.lastSequence ?? 0n;
    if (afterSequence === undefined || BigInt(afterSequence) > latest)
      return { events: [], nextSequence: latest.toString() };
    const events = await this.prisma.accountEvent.findMany({
      where: {
        userId,
        sequence: { gt: BigInt(afterSequence), lte: latest },
        eventType: { startsWith: "prediction.position." },
      },
      orderBy: { sequence: "asc" },
      take: 100,
    });
    return {
      events: events.map((e) => ({
        sequence: e.sequence.toString(),
        type: e.eventType,
        payload: e.payload,
      })),
      nextSequence: (events.length === 100
        ? events.at(-1)!.sequence
        : latest
      ).toString(),
    };
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
      const previous = await tx.predictionPosition.findFirst({
        where: { questionId, userId, mode },
        select: { side: true },
      });
      if (previous && previous.side !== body.side)
        this.error(
          "SIDE_LOCKED",
          "You already chose the other side. You can add to your existing side only.",
          409,
        );
      const eligible = await tx.user.findUnique({
        where: { id: userId },
        select: { tradingEnabled: true },
      });
      if (!eligible?.tradingEnabled)
        this.error(
          "ACCOUNT_RESTRICTED",
          "Prediction participation is restricted for this account.",
          403,
        );
      if (count >= 500)
        this.error(
          "QUESTION_FULL",
          "This question has reached its 500-entry capacity.",
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
        data: {
          [poolField]: { increment: stake },
          ...(!previous ? { participantCount: { increment: 1 } } : {}),
        },
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
        OR: [
          { nextSettlementAt: null },
          { nextSettlementAt: { lte: new Date() } },
        ],
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
        const question = await this.prisma.predictionQuestion.findUnique({
          where: { id: item.id },
          select: { expiresAt: true },
        });
        if (
          error instanceof ApiErrorException &&
          error.code === "CONTRACT_PRICE_UNAVAILABLE" &&
          question &&
          Date.now() - question.expiresAt.getTime() >= 24 * 60 * 60_000
        ) {
          await this.cancel(
            item.id,
            "The original expiry price was unavailable for 24 hours. All stakes were refunded.",
          );
          continue;
        }
        Logger.warn(
          `Question ${item.id} remains pending: ${error instanceof Error ? error.name : "UnknownError"}`,
          "PredictionSettlement",
        );
        // An unavailable old observation must not starve later due questions.
        await this.prisma.predictionQuestion.updateMany({
          where: { id: item.id, status: "OPEN" },
          data: {
            nextSettlementAt: new Date(Date.now() + 60_000),
            lastSettlementError:
              error instanceof ApiErrorException
                ? error.code
                : "SETTLEMENT_RETRY_REQUIRED",
          },
        });
      }
    }
    return { examined: due.length, settled };
  }

  async report(userId: string, questionId: string, reason: string) {
    await this.get(questionId);
    return this.prisma.predictionReport.upsert({
      where: { questionId_reporterId: { questionId, reporterId: userId } },
      create: { questionId, reporterId: userId, reason: reason.trim() },
      update: {},
      select: { id: true, status: true },
    });
  }

  async reports(cursor?: string) {
    const rows = await this.prisma.predictionReport.findMany({
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
      take: 21,
      include: { question: { include: questionInclude } },
    });
    const items = rows
      .slice(0, 20)
      .map((row) => ({ ...row, question: this.question(row.question) }));
    return { items, nextCursor: rows.length > 20 ? items.at(-1)?.id : null };
  }

  async resolveReport(id: string, reason: string, adminId: string) {
    return this.serializable(async (tx) => {
      const report = await tx.predictionReport.update({
        where: { id },
        data: {
          status: "RESOLVED",
          resolutionNote: reason.trim(),
          resolvedAt: new Date(),
        },
      });
      await this.audit(tx, adminId, "PREDICTION_REPORT_RESOLVED", id, reason);
      return report;
    });
  }

  async restrictCreator(
    userId: string,
    enabled: boolean,
    reason: string,
    adminId: string,
  ) {
    return this.serializable(async (tx) => {
      await tx.user.update({
        where: { id: userId },
        data: { predictionCreationEnabled: enabled },
      });
      await this.audit(
        tx,
        adminId,
        "PREDICTION_CREATION_PERMISSION",
        userId,
        reason,
        { enabled },
      );
      return { userId, enabled };
    });
  }

  private audit(
    tx: Prisma.TransactionClient,
    adminId: string | undefined,
    action: string,
    resourceId: string,
    reason: string,
    extra = {},
  ) {
    return tx.auditLog.create({
      data: {
        actorType: adminId ? "ADMIN" : "SYSTEM",
        actorAdminId: adminId ?? null,
        action,
        resourceType: "Prediction",
        resourceId,
        requestId: `prediction:${resourceId}`,
        newValue: { reason: reason.trim(), ...extra },
      },
    });
  }

  async cancel(questionId: string, reason: string, adminId?: string) {
    const response = await this.serializable(async (tx) => {
      await tx.$queryRaw`SELECT id FROM prediction_questions WHERE id = ${questionId}::uuid FOR UPDATE`;
      const question = await tx.predictionQuestion.findUnique({
        where: { id: questionId },
        include: { positions: true },
      });
      if (!question)
        this.error("QUESTION_NOT_FOUND", "Prediction not found.", 404);
      if (question.status === "CANCELLED")
        return { id: questionId, refunded: true };
      if (question.status !== "OPEN")
        this.error(
          "QUESTION_SETTLED",
          "A resolved prediction cannot be cancelled.",
          409,
        );
      for (const position of [...question.positions].sort(
        (a, b) =>
          a.accountId.localeCompare(b.accountId) || a.id.localeCompare(b.id),
      )) {
        if (position.result !== "PENDING") continue;
        const wallet = await this.ledger.lockWallet(tx, position.accountId);
        if (wallet.lockedProjection.lessThan(position.stake))
          this.error(
            "LEDGER_PROJECTION_MISMATCH",
            "Locked funds do not reconcile.",
            409,
          );
        const accounts = await this.ledger.ensureAccountLedgerAccounts(
          tx,
          position.accountId,
          position.mode,
        );
        await this.ledger.post(tx, {
          type: LedgerTransactionType.TRADE_SETTLEMENT,
          idempotencyKey: `prediction-refund:${position.id}`,
          description: "Cancelled prediction: full stake refund",
          reference: position.id,
          entries: [
            {
              ledgerAccountId: accounts.locked,
              direction: LedgerDirection.DEBIT,
              amount: position.stake,
            },
            {
              ledgerAccountId: accounts.available,
              direction: LedgerDirection.CREDIT,
              amount: position.stake,
            },
          ],
        });
        await tx.wallet.update({
          where: { id: wallet.id },
          data: {
            lockedProjection: { decrement: position.stake },
            availableProjection: { increment: position.stake },
          },
        });
        const updated = await tx.predictionPosition.update({
          where: { id: position.id },
          data: {
            result: "REFUNDED",
            payoutAmount: position.stake,
            settledAt: new Date(),
          },
        });
        await this.outbox.enqueueAccount(tx, position.userId, {
          aggregateType: "PredictionPosition",
          aggregateId: position.id,
          eventType: "prediction.position.refunded",
          payload: this.positionResponse(updated),
        });
        await tx.notification.create({
          data: {
            userId: position.userId,
            type: "PREDICTION_RESULT",
            titleKey: "prediction.refunded",
            bodyKey: "prediction.result",
            data: {
              questionId,
              result: "REFUNDED",
              payoutAmount: position.stake.toFixed(2),
              accountMode: position.mode,
            },
          },
        });
      }
      await tx.predictionQuestion.update({
        where: { id: questionId },
        data: {
          status: "CANCELLED",
          cancellationReason: reason.trim(),
          cancelledAt: new Date(),
        },
      });
      await this.audit(tx, adminId, "PREDICTION_CANCELLED", questionId, reason);
      return { id: questionId, refunded: true };
    });
    this.gateway.changed(questionId);
    return response;
  }

  async participants(questionId: string, cursor?: string) {
    const rows = await this.prisma.predictionPosition.findMany({
      where: { questionId },
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      take: 21,
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
      include: {
        user: { select: { id: true, profile: { select: { fullName: true } } } },
      },
    });
    const items = rows.slice(0, 20).map((row) => ({
      ...this.positionResponse(row),
      userId: row.userId,
      name: row.user.profile?.fullName ?? "Zettax member",
    }));
    return { items, nextCursor: rows.length > 20 ? items.at(-1)?.id : null };
  }

  async retrySettlement(questionId: string, adminId?: string) {
    await this.prisma.$transaction((tx) =>
      this.audit(
        tx,
        adminId,
        "PREDICTION_SETTLEMENT_RETRY",
        questionId,
        "Retry original archived expiry observation",
      ),
    );
    return { settled: await this.settleOne(questionId) };
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
        const hasWinningStake = question.positions.some(
          (entry) => entry.mode === position.mode && entry.side === outcome,
        );
        const result = !hasWinningStake
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
        await tx.notification.create({
          data: {
            userId: position.userId,
            type: "PREDICTION_RESULT",
            titleKey: "prediction.settled",
            bodyKey: "prediction.result",
            data: {
              questionId,
              result,
              payoutAmount: payout.toFixed(2),
              accountMode: position.mode,
            },
          },
        });
      }
      await tx.predictionQuestion.update({
        where: { id: questionId },
        data: {
          status: PredictionQuestionStatus.SETTLED,
          nextSettlementAt: null,
          lastSettlementError: null,
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
          !(
            ["P2034", "P2002"].includes(error.code) ||
            (error.code === "P2010" && error.meta?.code === "40001")
          ) ||
          attempt === 2
        )
          throw error;
      }
    }
    throw new Error("Prediction transaction unavailable");
  }
}
