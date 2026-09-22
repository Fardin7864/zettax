import {
  Body,
  Controller,
  Get,
  Module,
  Param,
  Post,
  Req,
  UseGuards,
} from "@nestjs/common";
import { IsIn, IsObject, IsString, MaxLength, validate } from "class-validator";
import { plainToInstance } from "class-transformer";
import { createHash } from "node:crypto";
import { Prisma } from "@prisma/client";
import {
  AdminModule,
  AdminGuard,
  type AdminRequest,
} from "../admin/admin.module";
import { PrismaService } from "../database/prisma.service";
import { ApiErrorException } from "../http/api-error";
import { UpdatePaymentMethodDto } from "../funding/funding.dto";
const permissions = {
  PAYMENT_METHOD: "funding.configure",
  TRADING_FEE: "trading.configure",
  USER_CONTROLS: "users.configure",
  ADMIN_ROLE: "admin.configure",
  KYC_REVIEW: "kyc.configure",
  MARKET: "trading.configure",
};
type Kind = keyof typeof permissions;
class ChangeDto {
  @IsIn(Object.keys(permissions)) kind!: Kind;
  @IsString() @MaxLength(100) targetId!: string;
  @IsObject() payload!: Prisma.InputJsonObject;
}
class ReviewDto {
  @IsIn(["APPROVED", "REJECTED"]) decision!: "APPROVED" | "REJECTED";
}
@Controller("admin/changes")
@UseGuards(AdminGuard)
class ChangesController {
  constructor(private readonly prisma: PrismaService) {}
  private require(req: AdminRequest, permission: string) {
    if (!req.user.permissions.includes(permission))
      throw new ApiErrorException(
        "ADMIN_PERMISSION_REQUIRED",
        `Permission ${permission} is required.`,
        403,
      );
  }
  @Get() list(@Req() req: AdminRequest) {
    this.require(req, "changes.review");
    return this.prisma.adminChange.findMany({
      orderBy: { createdAt: "desc" },
      take: 100,
    });
  }
  @Post() async create(@Req() req: AdminRequest, @Body() body: ChangeDto) {
    this.require(req, permissions[body.kind]);
    await this.validate(body.kind, body.payload);
    return this.prisma.$transaction(async (tx) => {
      const before = await this.snapshot(tx, body.kind, body.targetId);
      const row = await tx.adminChange.create({
        data: {
          ...body,
          fingerprint: this.hash(before),
          requestedBy: req.user.adminId,
        },
      });
      await this.audit(tx, req, "ADMIN_CHANGE_REQUESTED", row.id, body.payload);
      return row;
    });
  }
  @Post(":id/review") async review(
    @Req() req: AdminRequest,
    @Param("id") id: string,
    @Body() body: ReviewDto,
  ) {
    this.require(req, "changes.review");
    return this.prisma.$transaction(
      async (tx) => {
        await tx.$queryRaw`SELECT id FROM admin_changes WHERE id=${id}::uuid FOR UPDATE`;
        const row = await tx.adminChange.findUniqueOrThrow({ where: { id } });
        if (row.status !== "PENDING" || row.requestedBy === req.user.adminId)
          throw new ApiErrorException(
            "INDEPENDENT_REVIEW_REQUIRED",
            "A different operator must review a pending change.",
            403,
          );
        const kind = row.kind as Kind;
        this.require(req, permissions[kind]);
        const before = await this.snapshot(tx, kind, row.targetId);
        if (
          body.decision === "APPROVED" &&
          this.hash(before) !== row.fingerprint
        )
          throw new ApiErrorException(
            "CONFIGURATION_CHANGED",
            "The underlying record changed. Reject this request and create a new one.",
            409,
          );
        const payload = row.payload as Prisma.InputJsonObject;
        await this.validate(kind, payload);
        if (body.decision === "APPROVED") {
          const maker = await tx.adminUser.findUnique({
            where: { id: row.requestedBy },
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
          if (
            !maker?.active ||
            !maker.assignments.some((a) =>
              a.role.permissions.some(
                (p) => p.permission.key === permissions[kind],
              ),
            )
          )
            throw new ApiErrorException(
              "MAKER_AUTHORITY_REVOKED",
              "The requesting operator no longer has authority for this change.",
              403,
            );
          if (kind === "PAYMENT_METHOD")
            await tx.paymentMethod.update({
              where: { id: row.targetId },
              data: plainToInstance(UpdatePaymentMethodDto, payload),
            });
          if (kind === "TRADING_FEE")
            await tx.systemConfig.upsert({
              where: { key: "trading.profitFeeRate" },
              create: {
                key: "trading.profitFeeRate",
                value: payload.rate as string,
                updatedBy: req.user.adminId,
              },
              update: {
                value: payload.rate as string,
                updatedBy: req.user.adminId,
              },
            });
          if (kind === "USER_CONTROLS") {
            if (
              Object.values(payload).includes(true) &&
              !(await tx.kycCase.findFirst({
                where: { userId: row.targetId, status: "APPROVED" },
              }))
            )
              throw new ApiErrorException(
                "KYC_REQUIRED",
                "Approved identity checks are required before enabling REAL account controls.",
                403,
              );
            await tx.user.update({
              where: { id: row.targetId },
              data: payload as {
                depositEnabled: boolean;
                withdrawalEnabled: boolean;
                tradingEnabled: boolean;
              },
            });
          }
          if (kind === "ADMIN_ROLE") {
            if ([req.user.adminId, row.requestedBy].includes(row.targetId))
              throw new ApiErrorException(
                "SELF_PRIVILEGE_CHANGE_BLOCKED",
                "Neither reviewer may be the administrator receiving a role change.",
                403,
              );
            const roleId = payload.roleId as string;
            await tx.role.findUniqueOrThrow({ where: { id: roleId } });
            if (payload.remove === true)
              await tx.adminRoleAssignment.deleteMany({
                where: { adminUserId: row.targetId, roleId },
              });
            else
              await tx.adminRoleAssignment.upsert({
                where: {
                  adminUserId_roleId: { adminUserId: row.targetId, roleId },
                },
                create: { adminUserId: row.targetId, roleId },
                update: {},
              });
          }
          if (kind === "MARKET")
            await tx.instrument.update({
              where: { id: row.targetId },
              data: { realEnabled: payload.realEnabled as boolean },
            });
          if (kind === "KYC_REVIEW") {
            const kyc = await tx.kycCase.findUniqueOrThrow({
              where: { id: row.targetId },
              include: { documents: true },
            });
            if (!["SUBMITTED", "UNDER_REVIEW"].includes(kyc.status))
              throw new ApiErrorException(
                "KYC_NOT_SUBMITTED",
                "Only submitted identity cases can be reviewed.",
                409,
              );
            if (
              payload.status === "APPROVED" &&
              (!kyc.documents.length ||
                kyc.documents.some((d) => d.scanStatus !== "CLEAN"))
            )
              throw new ApiErrorException(
                "KYC_DOCUMENTS_REQUIRED",
                "Clean identity documents are required.",
                403,
              );
            await tx.kycCase.update({
              where: { id: row.targetId },
              data: {
                status: payload.status as
                  "APPROVED" | "REJECTED" | "MORE_INFO_REQUIRED",
                adminNotes: payload.notes as string,
                reviewedBy: req.user.adminId,
                reviewedAt: new Date(),
              },
            });
          }
        }
        const updated = await tx.adminChange.update({
          where: { id },
          data: {
            status: body.decision,
            reviewedBy: req.user.adminId,
            reviewedAt: new Date(),
          },
        });
        await this.audit(tx, req, "ADMIN_CHANGE_REVIEWED", id, {
          kind,
          decision: body.decision,
          payload,
        });
        return updated;
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );
  }
  private async snapshot(
    tx: Prisma.TransactionClient,
    kind: Kind,
    id: string,
  ): Promise<unknown> {
    switch (kind) {
      case "PAYMENT_METHOD":
        return tx.paymentMethod.findUniqueOrThrow({ where: { id } });
      case "TRADING_FEE":
        return tx.systemConfig.findUnique({
          where: { key: "trading.profitFeeRate" },
        });
      case "USER_CONTROLS":
        return tx.user.findUniqueOrThrow({
          where: { id },
          select: {
            id: true,
            depositEnabled: true,
            withdrawalEnabled: true,
            tradingEnabled: true,
          },
        });
      case "ADMIN_ROLE":
        return tx.adminUser.findUniqueOrThrow({
          where: { id },
          select: { id: true, active: true, assignments: true },
        });
      case "KYC_REVIEW":
        return tx.kycCase.findUniqueOrThrow({ where: { id } });
      case "MARKET":
        return tx.instrument.findUniqueOrThrow({ where: { id } });
    }
  }
  private hash(value: unknown) {
    return createHash("sha256").update(JSON.stringify(value)).digest("hex");
  }
  private async validate(kind: Kind, p: Prisma.InputJsonObject) {
    let valid = true;
    if (kind === "PAYMENT_METHOD") {
      const errors = await validate(
        plainToInstance(UpdatePaymentMethodDto, p),
        { whitelist: true, forbidNonWhitelisted: true },
      );
      valid =
        !errors.length &&
        typeof p.minimumDeposit === "string" &&
        /^\d+(\.\d{1,2})?$/.test(p.minimumDeposit) &&
        typeof p.maximumDeposit === "string" &&
        /^\d+(\.\d{1,2})?$/.test(p.maximumDeposit) &&
        Number(p.minimumDeposit) > 0 &&
        Number(p.maximumDeposit) >= Number(p.minimumDeposit) &&
        typeof p.instructions === "string" &&
        p.instructions.trim().length >= 10;
    }
    if (kind === "TRADING_FEE")
      valid =
        Object.keys(p).length === 1 &&
        typeof p.rate === "string" &&
        /^(0(\.\d{1,6})?|1(\.0{1,6})?)$/.test(p.rate);
    if (kind === "USER_CONTROLS")
      valid =
        Object.keys(p).length === 3 &&
        ["depositEnabled", "withdrawalEnabled", "tradingEnabled"].every(
          (key) => typeof p[key] === "boolean",
        );
    if (kind === "ADMIN_ROLE")
      valid =
        Object.keys(p).length === 2 &&
        typeof p.roleId === "string" &&
        typeof p.remove === "boolean";
    if (kind === "MARKET")
      valid = Object.keys(p).length === 1 && typeof p.realEnabled === "boolean";
    if (kind === "KYC_REVIEW")
      valid =
        Object.keys(p).length === 2 &&
        typeof p.status === "string" &&
        ["APPROVED", "REJECTED", "MORE_INFO_REQUIRED"].includes(p.status) &&
        typeof p.notes === "string" &&
        p.notes.length >= 20;
    if (!valid)
      throw new ApiErrorException(
        "INVALID_CHANGE",
        "The proposed change is incomplete or invalid.",
        400,
      );
  }
  private audit(
    tx: Prisma.TransactionClient,
    req: AdminRequest,
    action: string,
    id: string,
    payload: Prisma.InputJsonValue,
  ) {
    return tx.auditLog.create({
      data: {
        actorType: "ADMIN",
        actorAdminId: req.user.adminId,
        action,
        resourceType: "AdminChange",
        resourceId: id,
        newValue: payload,
        requestId: req.requestId,
      },
    });
  }
}
@Module({ imports: [AdminModule], controllers: [ChangesController] })
export class ChangesModule {}
