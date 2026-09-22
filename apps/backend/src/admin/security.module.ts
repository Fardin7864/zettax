import {
  Body,
  Controller,
  Get,
  Module,
  Post,
  Req,
  UseGuards,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import {
  generateRegistrationOptions,
  verifyRegistrationResponse,
  generateAuthenticationOptions,
  verifyAuthenticationResponse,
  type RegistrationResponseJSON,
  type AuthenticationResponseJSON,
} from "@simplewebauthn/server";
import { IsObject, IsString, IsIn, IsUUID, MaxLength } from "class-validator";
import { Throttle } from "@nestjs/throttler";
import * as argon2 from "argon2";
import {
  AdminModule,
  AdminGuard,
  AdminSession,
  type AdminRequest,
} from "./admin.module";
import { PrismaService } from "../database/prisma.service";
import { ApiErrorException } from "../http/api-error";
class OptionsDto {
  @IsIn(["REGISTER", "VERIFY"]) kind!: "REGISTER" | "VERIFY";
}
class PasswordStepUpDto {
  @IsString() @MaxLength(200) password!: string;
}
class CredentialDto {
  @IsUUID() challengeId!: string;
  @IsObject() response!: RegistrationResponseJSON & AuthenticationResponseJSON;
  @IsString() kind!: string;
}
@Controller("admin/auth")
@UseGuards(AdminGuard)
class SecurityController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly sessions: AdminSession,
  ) {}
  @Post("confirm-password")
  @Throttle({ default: { limit: 5, ttl: 60000 } })
  async confirmPassword(
    @Req() req: AdminRequest,
    @Body() body: PasswordStepUpDto,
  ) {
    const failures = await this.prisma.auditLog.count({
      where: {
        actorAdminId: req.user.adminId,
        action: "ADMIN_PASSWORD_CONFIRM_FAILED",
        createdAt: { gte: new Date(Date.now() - 900000) },
      },
    });
    if (failures >= 5)
      throw new ApiErrorException(
        "ADMIN_CONFIRM_LOCKED",
        "Too many failed confirmations. Try again after 15 minutes.",
        429,
      );
    const admin = await this.prisma.adminUser.findUniqueOrThrow({
      where: { id: req.user.adminId },
    });
    const verified =
      admin.active && (await argon2.verify(admin.passwordHash, body.password));
    await this.prisma.auditLog.create({
      data: {
        actorType: "ADMIN",
        actorAdminId: admin.id,
        action: verified
          ? "ADMIN_PASSWORD_CONFIRMED"
          : "ADMIN_PASSWORD_CONFIRM_FAILED",
        resourceType: "AdminUser",
        resourceId: admin.id,
        requestId: req.requestId,
      },
    });
    if (!verified)
      throw new ApiErrorException(
        "ADMIN_CONFIRM_FAILED",
        "Password confirmation failed.",
        403,
      );
    return {
      accessToken: await this.sessions.sign(admin.id, Date.now() + 300000),
      expiresIn: 900,
    };
  }
  @Get("me") async me(@Req() req: AdminRequest) {
    return {
      ...req.user,
      email: (
        await this.prisma.adminUser.findUniqueOrThrow({
          where: { id: req.user.adminId },
        })
      ).email,
      securityKeys: await this.prisma.adminCredential.count({
        where: { adminId: req.user.adminId },
      }),
    };
  }
  @Post("security-options") async options(
    @Req() req: AdminRequest,
    @Body() body: OptionsDto,
  ) {
    const keys = await this.prisma.adminCredential.findMany({
      where: { adminId: req.user.adminId },
    });
    if (
      body.kind === "REGISTER" &&
      keys.length &&
      (!req.user.stepUpUntil || req.user.stepUpUntil < Date.now())
    )
      throw new ApiErrorException(
        "ADMIN_STEP_UP_REQUIRED",
        "Verify an existing key before adding another.",
        403,
      );
    const rpID = this.config.get<string>("WEBAUTHN_RP_ID", "localhost");
    const options =
      body.kind === "REGISTER"
        ? await generateRegistrationOptions({
            rpName: "Zettax Operations",
            rpID,
            userName: (
              await this.prisma.adminUser.findUniqueOrThrow({
                where: { id: req.user.adminId },
              })
            ).email,
            userID: Buffer.from(req.user.adminId),
            attestationType: "none",
            excludeCredentials: keys.map((k) => ({ id: k.id })),
            authenticatorSelection: {
              authenticatorAttachment: "cross-platform",
              userVerification: "required",
              residentKey: "preferred",
            },
          })
        : await generateAuthenticationOptions({
            rpID,
            allowCredentials: keys.map((k) => ({ id: k.id })),
            userVerification: "required",
          });
    if (body.kind === "VERIFY" && !keys.length)
      throw new ApiErrorException(
        "ADMIN_KEY_REQUIRED",
        "Register a hardware security key first.",
        403,
      );
    const challenge = await this.prisma.adminChallenge.create({
      data: {
        adminId: req.user.adminId,
        kind: body.kind,
        challenge: options.challenge,
        expiresAt: new Date(Date.now() + 120000),
      },
    });
    return { challengeId: challenge.id, options };
  }
  @Post("security-verify") async verify(
    @Req() req: AdminRequest,
    @Body() body: CredentialDto,
  ) {
    const challenge = await this.prisma.adminChallenge.findUnique({
      where: { id: body.challengeId },
    });
    if (
      !challenge ||
      challenge.adminId !== req.user.adminId ||
      challenge.kind !== body.kind ||
      challenge.expiresAt.getTime() < Date.now() ||
      challenge.consumedAt
    )
      throw new ApiErrorException(
        "ADMIN_CHALLENGE_INVALID",
        "Request a new security challenge.",
        400,
      );
    const consumed = await this.prisma.adminChallenge.updateMany({
      where: { id: challenge.id, consumedAt: null },
      data: { consumedAt: new Date() },
    });
    if (consumed.count !== 1)
      throw new ApiErrorException(
        "ADMIN_CHALLENGE_USED",
        "Challenge already used.",
        409,
      );
    const expectedOrigin = this.config.get<string>(
        "WEBAUTHN_ORIGIN",
        "http://localhost:3001",
      ),
      expectedRPID = this.config.get<string>("WEBAUTHN_RP_ID", "localhost");
    if (body.kind === "REGISTER") {
      if (
        (await this.prisma.adminCredential.count({
          where: { adminId: req.user.adminId },
        })) &&
        (!req.user.stepUpUntil || req.user.stepUpUntil < Date.now())
      )
        throw new ApiErrorException(
          "ADMIN_STEP_UP_REQUIRED",
          "Verify an existing key.",
          403,
        );
      const result = await verifyRegistrationResponse({
        response: body.response,
        expectedChallenge: challenge.challenge,
        expectedOrigin,
        expectedRPID,
        requireUserVerification: true,
      });
      if (
        !result.verified ||
        result.registrationInfo.credentialDeviceType !== "singleDevice"
      )
        throw new ApiErrorException(
          "ADMIN_HARDWARE_KEY_REQUIRED",
          "Use a non-synced hardware security key.",
          403,
        );
      const { credential } = result.registrationInfo;
      await this.prisma.adminCredential.create({
        data: {
          id: credential.id,
          adminId: req.user.adminId,
          publicKey: Buffer.from(credential.publicKey),
          counter: BigInt(credential.counter),
          deviceType: "singleDevice",
        },
      });
    } else {
      const key = await this.prisma.adminCredential.findUnique({
        where: { id: body.response.id },
      });
      if (!key || key.adminId !== req.user.adminId)
        throw new ApiErrorException(
          "ADMIN_KEY_INVALID",
          "Unknown security key.",
          403,
        );
      const result = await verifyAuthenticationResponse({
        response: body.response,
        expectedChallenge: challenge.challenge,
        expectedOrigin,
        expectedRPID,
        credential: {
          id: key.id,
          publicKey: key.publicKey,
          counter: Number(key.counter),
        },
        requireUserVerification: true,
      });
      if (!result.verified)
        throw new ApiErrorException(
          "ADMIN_KEY_INVALID",
          "Key verification failed.",
          403,
        );
      const updated = await this.prisma.adminCredential.updateMany({
        where: { id: key.id, counter: key.counter },
        data: { counter: BigInt(result.authenticationInfo.newCounter) },
      });
      if (updated.count !== 1)
        throw new ApiErrorException(
          "ADMIN_KEY_REPLAY",
          "Request a fresh security-key challenge.",
          409,
        );
    }
    await this.prisma.auditLog.create({
      data: {
        actorType: "ADMIN",
        actorAdminId: req.user.adminId,
        action: `ADMIN_KEY_${body.kind}`,
        resourceType: "AdminUser",
        resourceId: req.user.adminId,
        requestId: req.requestId,
      },
    });
    return {
      accessToken: await this.sessions.sign(
        req.user.adminId,
        Date.now() + 300000,
      ),
      expiresIn: 900,
    };
  }
}
@Module({ imports: [AdminModule], controllers: [SecurityController] })
export class SecurityModule {}
