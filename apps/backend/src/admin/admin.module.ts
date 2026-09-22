import {
  Body,
  CanActivate,
  Controller,
  ExecutionContext,
  Get,
  Injectable,
  Module,
  Post,
  Req,
  UseGuards,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { JwtModule, JwtService } from "@nestjs/jwt";
import { Throttle } from "@nestjs/throttler";
import { IsEmail, IsString, Matches, MaxLength } from "class-validator";
import { Prisma } from "@prisma/client";
import * as argon2 from "argon2";
import { createHmac } from "node:crypto";
import type { Request } from "express";
import { PrismaService } from "../database/prisma.service";
import { ApiErrorException } from "../http/api-error";

export type AdminRequest = Request & {
  requestId: string;
  user: { adminId: string; permissions: string[]; stepUpUntil?: number };
};
class AdminLoginDto {
  @IsEmail() email!: string;
  @IsString() @MaxLength(200) password!: string;
}
class ProfitFeeDto {
  @IsString() @Matches(/^(?:0(?:\.\d{1,6})?|1(?:\.0{1,6})?)$/) rate!: string;
}
@Injectable()
export class AdminSession {
  constructor(
    private readonly config: ConfigService,
    private readonly jwt: JwtService,
  ) {}
  private secret() {
    const key = this.config.get<string>("JWT_ACCESS_SECRET");
    if (!key) throw new Error("Missing session secret");
    return createHmac("sha256", key)
      .update("primevest-admin-session-v1")
      .digest("hex");
  }
  sign(id: string, stepUpUntil?: number) {
    return this.jwt.signAsync(
      { ...(stepUpUntil ? { stepUpUntil } : {}) },
      {
        subject: id,
        audience: "primevest-admin",
        issuer: "primevest-api",
        expiresIn: "15m",
        secret: this.secret(),
      },
    );
  }
  verify(token: string) {
    return this.jwt.verifyAsync<{
      sub: string;
      stepUpUntil?: number;
      iat: number;
    }>(token, {
      audience: "primevest-admin",
      issuer: "primevest-api",
      algorithms: ["HS256"],
      secret: this.secret(),
    });
  }
}
@Injectable()
export class AdminGuard implements CanActivate {
  constructor(
    private readonly session: AdminSession,
    private readonly prisma: PrismaService,
  ) {}
  async canActivate(context: ExecutionContext) {
    const req = context.switchToHttp().getRequest<AdminRequest>();
    try {
      const header = req.header("authorization");
      if (!header?.startsWith("Bearer ")) throw new Error();
      const token = await this.session.verify(header.slice(7));
      const admin = await this.prisma.adminUser.findUnique({
        where: { id: token.sub },
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
      if (!admin?.active) throw new Error();
      req.user = {
        adminId: admin.id,
        ...(token.stepUpUntil ? { stepUpUntil: token.stepUpUntil } : {}),
        permissions: admin.assignments.flatMap((a) =>
          a.role.permissions.map((p) => p.permission.key),
        ),
      };
      return true;
    } catch (error) {
      if (error instanceof ApiErrorException) throw error;
      throw new ApiErrorException(
        "ADMIN_AUTH_REQUIRED",
        "Sign in to the administrator account.",
        401,
      );
    }
  }
}
@Controller("admin")
class AdminController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly session: AdminSession,
  ) {}
  @Post("auth/login")
  @Throttle({ default: { limit: 5, ttl: 60000 } })
  async login(@Body() body: AdminLoginDto) {
    const admin = await this.prisma.adminUser.findUnique({
      where: { email: body.email.toLowerCase().trim() },
    });
    if (
      !admin?.active ||
      !(await argon2.verify(admin.passwordHash, body.password))
    ) {
      throw new ApiErrorException(
        "ADMIN_LOGIN_FAILED",
        "Email or password is incorrect.",
        401,
      );
    }
    return { accessToken: await this.session.sign(admin.id), expiresIn: 900 };
  }
  @Get("trading-settings")
  @UseGuards(AdminGuard)
  async settings(@Req() req: AdminRequest) {
    this.configure(req);
    const row = await this.prisma.systemConfig.findUnique({
      where: { key: "trading.profitFeeRate" },
    });
    return {
      profitFeeRate: row?.value ?? "0",
      minimumStakeBdt: "10.00",
      maximumStake: null,
      minimumDurationSeconds: 30,
      maximumDurationSeconds: 31536000,
    };
  }
  @UseGuards(AdminGuard)
  async update(@Req() req: AdminRequest, @Body() body: ProfitFeeDto) {
    this.configure(req);
    const value = new Prisma.Decimal(body.rate).toFixed();
    return this.prisma.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT key FROM system_config WHERE key = 'trading.profitFeeRate' FOR UPDATE`;
      const previous = await tx.systemConfig.findUnique({
        where: { key: "trading.profitFeeRate" },
      });
      await tx.systemConfig.upsert({
        where: { key: "trading.profitFeeRate" },
        create: {
          key: "trading.profitFeeRate",
          value,
          updatedBy: req.user.adminId,
        },
        update: { value, updatedBy: req.user.adminId },
      });
      await tx.auditLog.create({
        data: {
          actorType: "ADMIN",
          actorAdminId: req.user.adminId,
          action: "PROFIT_FEE_UPDATED",
          resourceType: "SystemConfig",
          resourceId: "trading.profitFeeRate",
          previousValue: previous?.value ?? "0",
          newValue: value,
          requestId: req.requestId,
        },
      });
      return { profitFeeRate: value };
    });
  }
  private configure(req: AdminRequest) {
    if (!req.user.permissions.includes("trading.configure"))
      throw new ApiErrorException(
        "ADMIN_PERMISSION_REQUIRED",
        "Trading configuration permission is required.",
        403,
      );
  }
}
@Module({
  imports: [JwtModule.register({})],
  providers: [AdminGuard, AdminSession],
  controllers: [AdminController],
  exports: [AdminGuard, AdminSession],
})
export class AdminModule {}
