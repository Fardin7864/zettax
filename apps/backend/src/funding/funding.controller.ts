import {
  Body,
  Controller,
  Get,
  Headers,
  HttpStatus,
  Param,
  Post,
  Query,
  Req,
  UseGuards,
  UploadedFile,
  UseInterceptors,
  Res,
} from "@nestjs/common";
import { ApiBearerAuth, ApiOperation, ApiTags } from "@nestjs/swagger";
import type { Request, Response } from "express";
import { FileInterceptor } from "@nestjs/platform-express";
import { Throttle } from "@nestjs/throttler";
import { EvidenceService, EVIDENCE_LIMIT } from "./evidence.service";
import { PrismaService } from "../database/prisma.service";
import { IsString, MinLength, MaxLength } from "class-validator";
class VerifyTransferDto {
  @IsString() @MinLength(5) @MaxLength(500) reference!: string;
}
import type { RequestWithId } from "../http/request-id.middleware";
import {
  AccessTokenGuard,
  type AuthenticatedRequest,
} from "../auth/access-token.guard";
import {
  CreateDepositDto,
  CreateWithdrawalDto,
  MarkWithdrawalPaidDto,
  RejectDepositDto,
  RejectWithdrawalDto,
  UpdatePaymentMethodDto,
  WithdrawalTransitionDto,
} from "./funding.dto";
import { fundingError } from "./funding.errors";
import { FundingService } from "./funding.service";
import { AdminDepositQueryDto, AdminWithdrawalQueryDto } from "./funding-pagination.dto";
import { AdminGuard } from "../admin/admin.module";
import { validateIdempotencyKey } from "./funding.validation";

type PrincipalRequest = RequestWithId & {
  user?: { sub?: string; adminId?: string; permissions?: string[] };
};

type UserRequest = RequestWithId & AuthenticatedRequest;

@ApiTags("funding")
@ApiBearerAuth()
@Controller()
export class FundingController {
  constructor(
    private readonly funding: FundingService,
    private readonly evidence: EvidenceService,
    private readonly prisma: PrismaService,
  ) {}
  @Post("evidence")
  @UseGuards(AccessTokenGuard)
  @Throttle({ default: { limit: 10, ttl: 60000 } })
  @UseInterceptors(
    FileInterceptor("file", {
      limits: { fileSize: EVIDENCE_LIMIT, files: 1, fields: 2 },
    }),
  )
  uploadEvidence(
    @Req() req: UserRequest,
    @UploadedFile() file: Express.Multer.File,
    @Body("purpose") purpose: string,
  ) {
    return this.evidence.upload(req.auth.userId, "USER", purpose, file);
  }
  @Post("admin/evidence")
  @UseGuards(AdminGuard)
  @UseInterceptors(
    FileInterceptor("file", {
      limits: { fileSize: EVIDENCE_LIMIT, files: 1, fields: 2 },
    }),
  )
  uploadAdminEvidence(
    @Req() req: PrincipalRequest,
    @UploadedFile() file: Express.Multer.File,
    @Body("purpose") purpose: string,
  ) {
    return this.evidence.upload(
      this.admin(req, "evidence.write"),
      "ADMIN",
      purpose,
      file,
    );
  }
  @Get("admin/evidence/:id")
  @UseGuards(AdminGuard)
  async readEvidence(
    @Req() req: PrincipalRequest,
    @Param("id") id: string,
    @Res() response: Response,
  ) {
    const adminId = this.admin(req, "evidence.read");
    const bytes = await this.evidence.read(id);
    await this.prisma.auditLog.create({
      data: {
        actorType: "ADMIN",
        actorAdminId: adminId,
        action: "EVIDENCE_VIEWED",
        resourceType: "EvidenceFile",
        resourceId: id,
        requestId: req.requestId,
      },
    });
    response
      .set({
        "Content-Type": "image/png",
        "Cache-Control": "no-store",
        "Content-Disposition": 'inline; filename="evidence.png"',
        "X-Content-Type-Options": "nosniff",
      })
      .send(bytes);
  }
  @Post("admin/deposits/:id/verify")
  @UseGuards(AdminGuard)
  verifyDeposit(
    @Req() req: PrincipalRequest,
    @Param("id") id: string,
    @Body() body: VerifyTransferDto,
  ) {
    return this.funding.verifyDeposit(
      id,
      this.admin(req, "deposit.verify"),
      body.reference,
      this.auditContext(req),
    );
  }

  @Get("deposits/payment-methods")
  @UseGuards(AccessTokenGuard)
  async listDepositMethods() {
    return { data: await this.funding.listPaymentMethods("DEPOSITS") };
  }

  @Get("withdrawals/payment-methods")
  @UseGuards(AccessTokenGuard)
  async listWithdrawalMethods() {
    return { data: await this.funding.listPaymentMethods("WITHDRAWALS") };
  }

  @Get("deposits")
  @UseGuards(AccessTokenGuard)
  async listDeposits(@Req() request: UserRequest) {
    return { data: await this.funding.listDeposits(this.userId(request)) };
  }

  @Post("deposits")
  @UseGuards(AccessTokenGuard)
  @ApiOperation({
    summary: "Submit a manual bKash/Nagad/Rocket deposit for admin review",
  })
  async createDeposit(
    @Req() request: UserRequest,
    @Headers("idempotency-key") key: string | undefined,
    @Body() body: CreateDepositDto,
  ) {
    return {
      data: await this.funding.createDeposit(
        this.userId(request),
        validateIdempotencyKey(key),
        body,
        this.auditContext(request),
      ),
    };
  }

  @Get("withdrawals")
  @UseGuards(AccessTokenGuard)
  async listWithdrawals(@Req() request: UserRequest) {
    return { data: await this.funding.listWithdrawals(this.userId(request)) };
  }

  @Post("withdrawals")
  @UseGuards(AccessTokenGuard)
  @ApiOperation({
    summary: "Create a KYC-gated manual withdrawal and lock funds",
  })
  async createWithdrawal(
    @Req() request: UserRequest,
    @Headers("idempotency-key") key: string | undefined,
    @Body() body: CreateWithdrawalDto,
  ) {
    return {
      data: await this.funding.createWithdrawal(
        this.userId(request),
        validateIdempotencyKey(key),
        body,
        this.auditContext(request),
      ),
    };
  }

  @Post("withdrawals/:id/cancel")
  @UseGuards(AccessTokenGuard)
  async cancelWithdrawal(@Req() request: UserRequest, @Param("id") id: string) {
    return {
      data: await this.funding.cancelWithdrawal(
        id,
        this.userId(request),
        this.auditContext(request),
      ),
    };
  }

  @Get("admin/deposits")
  @UseGuards(AdminGuard)
  async adminDeposits(
    @Req() request: PrincipalRequest,
    @Query() query: AdminDepositQueryDto,
  ) {
    this.admin(request, "deposit.read");
    return { data: await this.funding.listDepositsForReview(query.status, query.page, query.pageSize) };
  }

  @Get("admin/payment-methods")
  @UseGuards(AdminGuard)
  async adminPaymentMethods(@Req() request: PrincipalRequest) {
    this.admin(request, "funding.configure");
    return { data: await this.funding.listPaymentMethodsForAdmin() };
  }

  @UseGuards(AdminGuard)
  async updatePaymentMethod(
    @Req() request: PrincipalRequest,
    @Param("id") id: string,
    @Body() body: UpdatePaymentMethodDto,
  ) {
    const adminId = this.admin(request, "funding.configure");
    return {
      data: await this.funding.updatePaymentMethod(
        id,
        adminId,
        body,
        this.auditContext(request),
      ),
    };
  }

  @Post("admin/deposits/:id/approve")
  @UseGuards(AdminGuard)
  async approveDeposit(
    @Req() request: PrincipalRequest,
    @Param("id") id: string,
  ) {
    const adminId = this.admin(request, "deposit.approve");
    return {
      data: await this.funding.approveDeposit(
        id,
        adminId,
        this.auditContext(request),
      ),
    };
  }

  @Post("admin/deposits/:id/reject")
  @UseGuards(AdminGuard)
  async rejectDeposit(
    @Req() request: PrincipalRequest,
    @Param("id") id: string,
    @Body() body: RejectDepositDto,
  ) {
    const adminId = this.admin(request, "deposit.approve");
    return {
      data: await this.funding.rejectDeposit(
        id,
        adminId,
        body.reason,
        this.auditContext(request),
      ),
    };
  }

  @Get("admin/withdrawals")
  @UseGuards(AdminGuard)
  async adminWithdrawals(
    @Req() request: PrincipalRequest,
    @Query() query: AdminWithdrawalQueryDto,
  ) {
    this.admin(request, "withdrawal.read");
    return { data: await this.funding.listWithdrawalsForReview(query.status, query.page, query.pageSize) };
  }

  @Post("admin/withdrawals/:id/transition")
  @UseGuards(AdminGuard)
  async transitionWithdrawal(
    @Req() request: PrincipalRequest,
    @Param("id") id: string,
    @Body() body: WithdrawalTransitionDto,
  ) {
    const permission =
      body.action === "START_PROCESSING"
        ? "withdrawal.mark_paid"
        : "withdrawal.approve";
    const adminId = this.admin(request, permission);
    return {
      data: await this.funding.transitionWithdrawal(
        id,
        adminId,
        body.action,
        this.auditContext(request),
      ),
    };
  }

  @Post("admin/withdrawals/:id/reject")
  @UseGuards(AdminGuard)
  async rejectWithdrawal(
    @Req() request: PrincipalRequest,
    @Param("id") id: string,
    @Body() body: RejectWithdrawalDto,
  ) {
    const adminId = this.admin(request, "withdrawal.approve");
    return {
      data: await this.funding.rejectWithdrawal(
        id,
        adminId,
        body.reason,
        this.auditContext(request),
      ),
    };
  }

  @Post("admin/withdrawals/:id/paid")
  @UseGuards(AdminGuard)
  async markWithdrawalPaid(
    @Req() request: PrincipalRequest,
    @Param("id") id: string,
    @Body() body: MarkWithdrawalPaidDto,
  ) {
    const adminId = this.admin(request, "withdrawal.mark_paid");
    return {
      data: await this.funding.markWithdrawalPaid(
        id,
        adminId,
        body,
        this.auditContext(request),
      ),
    };
  }

  @Post("admin/withdrawals/:id/done")
  @UseGuards(AdminGuard)
  async completeVirtualWithdrawal(
    @Req() request: PrincipalRequest,
    @Param("id") id: string,
  ) {
    const adminId = this.admin(request, "withdrawal.mark_paid");
    return { data: await this.funding.completeVirtualWithdrawal(id, adminId, this.auditContext(request)) };
  }

  private userId(request: UserRequest): string {
    return request.auth.userId;
  }

  private admin(request: PrincipalRequest, permission: string): string {
    const adminId = request.user?.adminId;
    if (!adminId)
      fundingError(
        "ADMIN_AUTH_REQUIRED",
        "Admin authentication is required",
        HttpStatus.UNAUTHORIZED,
      );
    if (!request.user?.permissions?.includes(permission)) {
      fundingError(
        "ADMIN_PERMISSION_REQUIRED",
        `Permission ${permission} is required`,
        HttpStatus.FORBIDDEN,
      );
    }
    return adminId;
  }

  private auditContext(request: PrincipalRequest) {
    return {
      requestId: request.requestId,
      ipAddress: request.ip,
      userAgent: (request as Request).header("user-agent"),
    };
  }
}
