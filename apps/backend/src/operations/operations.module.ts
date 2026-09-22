import {
  Body,
  Controller,
  Get,
  Module,
  Param,
  Post,
  Query,
  Req,
  UseGuards,
} from "@nestjs/common";
import {
  IsString,
  IsIn,
  IsDateString,
  IsUUID,
  Matches,
  MinLength,
  MaxLength,
  IsOptional,
} from "class-validator";
import { Prisma } from "@prisma/client";
import {
  AdminModule,
  AdminGuard,
  type AdminRequest,
} from "../admin/admin.module";
import {
  ControlModule,
  ControlService,
  RELEASE_GATES,
} from "./control.service";
import { PrismaService } from "../database/prisma.service";
import { ApiErrorException } from "../http/api-error";
import { ComplianceModule } from "../compliance/compliance.module";
import { ComplianceService } from "../compliance/compliance.service";
class TreasuryDto {
  @IsString() @MinLength(5) @MaxLength(120) accountReference!: string;
  @IsIn(["CUSTOMER", "RESERVE"]) category!: string;
  @IsString() @Matches(/^\d+(\.\d{1,2})?$/) balance!: string;
  @IsDateString() asOf!: string;
  @IsUUID() evidenceId!: string;
  @IsString() @MinLength(10) @MaxLength(2000) notes!: string;
}
class ReviewDto {
  @IsIn(["APPROVED", "REJECTED"]) decision!: "APPROVED" | "REJECTED";
}
class ApprovalDto {
  @IsIn(RELEASE_GATES) gate!: string;
  @IsOptional() @IsUUID() evidenceId?: string;
  @IsOptional()
  @IsString()
  @MinLength(20)
  @MaxLength(1000)
  officeReference?: string;
  @IsString() @MinLength(20) @MaxLength(2000) notes!: string;
  @IsDateString() expiresAt!: string;
}
@Controller("admin")
@UseGuards(AdminGuard)
class OperationsController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly controls: ControlService,
    private readonly compliance: ComplianceService,
  ) {}
  private permission(req: AdminRequest, key: string) {
    if (!req.user.permissions.includes(key))
      throw new ApiErrorException(
        "ADMIN_PERMISSION_REQUIRED",
        `Permission ${key} is required.`,
        403,
      );
  }
  @Get("overview") async overview(@Req() req: AdminRequest) {
    if (!req.user.permissions.includes("operations.read")) {
      this.permission(req, "funding.overview");
      return {
        config: this.compliance.publicConfig(),
        pendingDeposits: await this.prisma.depositRequest.count({
          where: { status: "PENDING_REVIEW" },
        }),
        pendingWithdrawals: await this.prisma.withdrawalRequest.count({
          where: {
            status: {
              in: ["REQUESTED", "UNDER_REVIEW", "APPROVED", "PROCESSING"],
            },
          },
        }),
      };
    }
    this.permission(req, "operations.read");
    return {
      config: this.compliance.publicConfig(),
      release: await this.controls.readiness(),
      users: await this.prisma.user.count(),
      pendingDeposits: await this.prisma.depositRequest.count({
        where: { status: "PENDING_REVIEW" },
      }),
      pendingWithdrawals: await this.prisma.withdrawalRequest.count({
        where: {
          status: {
            in: ["REQUESTED", "UNDER_REVIEW", "APPROVED", "PROCESSING"],
          },
        },
      }),
    };
  }
  @Get("records/:area") async records(
    @Req() req: AdminRequest,
    @Param("area") area: string,
    @Query("page") rawPage = "1",
    @Query("search") search = "",
  ) {
    this.permission(req, "operations.read");
    const page = Math.max(1, Math.min(10000, Math.floor(Number(rawPage)) || 1)),
      take = 50,
      skip = (page - 1) * take;
    let items: unknown;
    switch (area) {
      case "users":
        items = await this.prisma.user.findMany({
          where: search
            ? { email: { contains: search, mode: "insensitive" } }
            : {},
          take,
          skip,
          orderBy: { createdAt: "desc" },
          select: {
            id: true,
            email: true,
            createdAt: true,
            depositEnabled: true,
            withdrawalEnabled: true,
            tradingEnabled: true,
            kycCases: { select: { id: true, status: true } },
          },
        });
        break;
      case "kyc":
        items = await this.prisma.kycCase.findMany({
          take,
          skip,
          orderBy: { createdAt: "desc" },
          include: { documents: true, user: { select: { email: true } } },
        });
        break;
      case "contracts":
        items = await this.prisma.timedContract.findMany({
          take,
          skip,
          orderBy: { entryTimestamp: "desc" },
          include: { settlement: true },
        });
        break;
      case "markets":
        items = await this.prisma.instrument.findMany({
          take,
          skip,
          orderBy: { slug: "asc" },
        });
        break;
      case "ledger":
        items = await this.prisma.ledgerTransaction.findMany({
          take,
          skip,
          orderBy: { postedAt: "desc" },
          include: { entries: true },
        });
        break;
      case "audit":
        this.permission(req, "audit.read");
        items = await this.prisma.auditLog.findMany({
          take,
          skip,
          orderBy: { createdAt: "desc" },
        });
        break;
      case "risk":
        items = await this.prisma.riskFlag.findMany({
          take,
          skip,
          orderBy: { createdAt: "desc" },
        });
        break;
      case "admins":
        this.permission(req, "admin.read");
        items = await this.prisma.adminUser.findMany({
          take,
          skip,
          select: {
            id: true,
            email: true,
            active: true,
            assignments: {
              include: {
                role: {
                  include: { permissions: { include: { permission: true } } },
                },
              },
            },
          },
        });
        break;
      case "roles":
        this.permission(req, "admin.read");
        items = await this.prisma.role.findMany({
          take,
          skip,
          orderBy: { name: "asc" },
          include: { permissions: { include: { permission: true } } },
        });
        break;
      default:
        throw new ApiErrorException(
          "RECORDS_NOT_FOUND",
          "Unknown record area.",
          404,
        );
    }
    return JSON.parse(
      JSON.stringify({ items, page, pageSize: take }, (_key, value: unknown) =>
        typeof value === "bigint" ? value.toString() : value,
      ),
    ) as Record<string, unknown>;
  }
  @Get("evidence") async evidence(
    @Req() req: AdminRequest,
    @Query("key") key: string,
  ) {
    this.permission(req, "evidence.read");
    return this.prisma.evidenceFile.findMany({
      where: { objectKey: key },
      select: {
        id: true,
        filename: true,
        purpose: true,
        status: true,
        sizeBytes: true,
        createdAt: true,
      },
      take: 1,
    });
  }
  @Get("treasury") async treasury(@Req() req: AdminRequest) {
    this.permission(req, "treasury.read");
    return {
      summary: await this.controls.treasury(),
      statements: await this.prisma.treasuryStatement.findMany({
        orderBy: { createdAt: "desc" },
        take: 100,
      }),
    };
  }
  @Post("treasury") async submitTreasury(
    @Req() req: AdminRequest,
    @Body() body: TreasuryDto,
  ) {
    this.permission(req, "treasury.submit");
    body.accountReference = body.accountReference.trim().toUpperCase();
    const asOf = new Date(body.asOf);
    if (
      asOf.getTime() > Date.now() + 60000 ||
      Date.now() - asOf.getTime() > 86400000
    )
      throw new ApiErrorException(
        "STATEMENT_STALE",
        "Use a statement from the last 24 hours.",
        400,
      );
    return this.prisma.$transaction(async (tx) => {
      const evidence = await tx.evidenceFile.findUnique({
        where: { id: body.evidenceId },
      });
      if (
        !evidence ||
        evidence.ownerId !== req.user.adminId ||
        evidence.ownerType !== "ADMIN" ||
        evidence.purpose !== "TREASURY" ||
        evidence.status !== "CLEAN" ||
        evidence.claimedBy
      )
        throw new ApiErrorException(
          "EVIDENCE_REQUIRED",
          "Attach your treasury statement image.",
          400,
        );
      const old = await tx.treasuryStatement.findFirst({
        where: { accountReference: body.accountReference },
        orderBy: { createdAt: "desc" },
      });
      if (old && old.category !== body.category)
        throw new ApiErrorException(
          "TREASURY_CATEGORY_CONFLICT",
          "An account cannot switch between customer funds and reserve capital.",
          409,
        );
      const row = await tx.treasuryStatement.create({
        data: {
          ...body,
          balance: new Prisma.Decimal(body.balance),
          asOf,
          submittedBy: req.user.adminId,
        },
      });
      await tx.evidenceFile.update({
        where: { id: evidence.id },
        data: { claimedBy: `treasury:${row.id}` },
      });
      await this.audit(tx, req, "TREASURY_STATEMENT_SUBMITTED", row.id, {
        balance: body.balance,
        category: body.category,
      });
      return row;
    });
  }
  @Post("treasury/:id/review") async reviewTreasury(
    @Req() req: AdminRequest,
    @Param("id") id: string,
    @Body() body: ReviewDto,
  ) {
    this.permission(req, "treasury.approve");
    return this.prisma.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT id FROM treasury_statements WHERE id=${id}::uuid FOR UPDATE`;
      const row = await tx.treasuryStatement.findUniqueOrThrow({
        where: { id },
      });
      if (row.status !== "PENDING" || row.submittedBy === req.user.adminId)
        throw new ApiErrorException(
          "INDEPENDENT_REVIEW_REQUIRED",
          "Another operator must review a pending statement.",
          403,
        );
      const result = await tx.treasuryStatement.update({
        where: { id },
        data: {
          status: body.decision,
          reviewedBy: req.user.adminId,
          reviewedAt: new Date(),
        },
      });
      await this.audit(tx, req, "TREASURY_STATEMENT_REVIEWED", id, {
        decision: body.decision,
      });
      return result;
    });
  }
  @Get("release") release(@Req() req: AdminRequest) {
    this.permission(req, "release.read");
    return this.controls.readiness();
  }
  @Post("release/approve") async approveRelease(
    @Req() req: AdminRequest,
    @Body() body: ApprovalDto,
  ) {
    this.permission(req, `release.${body.gate.toLowerCase()}`);
    const office = body.officeReference?.trim();
    if (
      (!body.evidenceId && !office) ||
      (body.evidenceId && office) ||
      (office && !["LEGAL", "COMPLIANCE"].includes(body.gate))
    )
      throw new ApiErrorException(
        "APPROVAL_EVIDENCE_REQUIRED",
        "Attach evidence, or provide an office record reference for a legal/compliance approval. Do not submit both.",
        400,
      );
    const expiresAt = new Date(body.expiresAt);
    if (
      expiresAt.getTime() <= Date.now() ||
      expiresAt.getTime() > Date.now() + 90 * 86400000
    )
      throw new ApiErrorException(
        "APPROVAL_EXPIRY_INVALID",
        "Approval must expire within 90 days.",
        400,
      );
    return this.prisma.$transaction(async (tx) => {
      const evidence = body.evidenceId
        ? await tx.evidenceFile.findUnique({
            where: { id: body.evidenceId },
          })
        : null;
      if (
        !office &&
        (!evidence ||
          evidence.ownerId !== req.user.adminId ||
          evidence.ownerType !== "ADMIN" ||
          evidence.purpose !== "RELEASE" ||
          evidence.status !== "CLEAN" ||
          evidence.claimedBy)
      )
        throw new ApiErrorException(
          "EVIDENCE_REQUIRED",
          "Attach your signed release evidence.",
          400,
        );
      const row = await tx.releaseApproval.create({
        data: {
          version: this.controls.version(),
          gate: body.gate,
          approvedBy: req.user.adminId,
          evidenceReference: office ? `office:${office}` : body.evidenceId!,
          notes: body.notes,
          expiresAt,
        },
      });
      if (evidence)
        await tx.evidenceFile.update({
          where: { id: evidence.id },
          data: { claimedBy: `release:${row.id}` },
        });
      await this.audit(tx, req, "RELEASE_GATE_SIGNED", row.id, {
        gate: body.gate,
        version: row.version,
      });
      return row;
    });
  }
  @Post("release/:id/revoke") async revoke(
    @Req() req: AdminRequest,
    @Param("id") id: string,
  ) {
    const row = await this.prisma.releaseApproval.findUniqueOrThrow({
      where: { id },
    });
    this.permission(req, `release.${row.gate.toLowerCase()}`);
    return this.prisma.$transaction(async (tx) => {
      const result = await tx.releaseApproval.update({
        where: { id },
        data: { revokedAt: new Date() },
      });
      await this.audit(tx, req, "RELEASE_GATE_REVOKED", id, { gate: row.gate });
      return result;
    });
  }
  private audit(
    tx: Prisma.TransactionClient,
    req: AdminRequest,
    action: string,
    id: string,
    data: Prisma.InputJsonValue,
  ) {
    return tx.auditLog.create({
      data: {
        actorType: "ADMIN",
        actorAdminId: req.user.adminId,
        action,
        resourceType: "Operations",
        resourceId: id,
        newValue: data,
        requestId: req.requestId,
      },
    });
  }
}
@Module({
  imports: [AdminModule, ControlModule, ComplianceModule],
  controllers: [OperationsController],
})
export class OperationsModule {}
