import { HttpStatus, Injectable } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { JwtService } from "@nestjs/jwt";
import { Prisma } from "@prisma/client";
import { OAuth2Client } from "google-auth-library";
import { randomUUID } from "node:crypto";
import { PrismaService } from "../database/prisma.service";
import { LedgerService } from "../database/ledger.service";
import { ApiErrorException } from "../http/api-error";
import type {
  AuthenticatedPrincipal,
  RefreshTokenPayload,
  RequestMetadata,
} from "./auth.types";
import type { LoginDto } from "./dto/login.dto";
import type { RegisterDto } from "./dto/register.dto";
import type { GoogleAuthDto } from "./dto/google-auth.dto";
import type { ChangePasswordDto } from "./dto/change-password.dto";
import { PasswordHasherService } from "./password-hasher.service";

const issuer = "primevest-api";
const audience = "primevest-mobile";

@Injectable()
export class AuthService {
  private readonly dummyHash: Promise<string>;
  private readonly googleClient = new OAuth2Client();

  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly hasher: PasswordHasherService,
    private readonly ledger: LedgerService,
  ) {
    this.dummyHash = this.hasher.hash(randomUUID());
  }

  async register(body: RegisterDto, metadata: RequestMetadata) {
    const email = body.email.trim().toLowerCase();
    const passwordHash = await this.hasher.hash(body.password);
    try {
      const user = await this.prisma.$transaction(async (transaction) => {
        const createdUser = await transaction.user.create({
          data: {
            email,
            passwordHash,
            security: { create: {} },
          },
        });
        await this.createAccounts(transaction, createdUser.id);
        return createdUser;
      });
      return this.establishSession(user, body, metadata);
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === "P2002"
      ) {
        throw new ApiErrorException(
          "AUTH_ACCOUNT_EXISTS",
          "An account already exists for these credentials.",
          HttpStatus.CONFLICT,
        );
      }
      throw error;
    }
  }

  async google(body: GoogleAuthDto, metadata: RequestMetadata) {
    const clientId = this.googleWebClientId;
    let payload;
    try {
      const ticket = await this.googleClient.verifyIdToken({
        idToken: body.idToken,
        audience: clientId,
      });
      payload = ticket.getPayload();
    } catch {
      throw new ApiErrorException(
        "AUTH_GOOGLE_TOKEN_INVALID",
        "Google could not verify this sign-in. Please try again.",
        HttpStatus.UNAUTHORIZED,
      );
    }

    const subject = payload?.sub;
    const email = payload?.email?.trim().toLowerCase();
    if (!subject || !email || payload?.email_verified !== true) {
      throw new ApiErrorException(
        "AUTH_GOOGLE_EMAIL_UNVERIFIED",
        "A verified Google email address is required.",
        HttpStatus.UNAUTHORIZED,
      );
    }

    const user = await this.prisma.$transaction(async (transaction) => {
      const identity = await transaction.externalIdentity.findUnique({
        where: {
          provider_providerSubject: {
            provider: "GOOGLE",
            providerSubject: subject,
          },
        },
        include: { user: true },
      });
      if (identity) {
        if (identity.providerEmail !== email) {
          await transaction.externalIdentity.update({
            where: { id: identity.id },
            data: { providerEmail: email },
          });
        }
        return identity.user;
      }

      const existingUser = await transaction.user.findUnique({
        where: { email },
      });
      let targetUser = existingUser;
      if (targetUser) {
        const googleIsAuthoritative =
          email.endsWith("@gmail.com") || Boolean(payload?.hd);
        if (!googleIsAuthoritative) {
          throw new ApiErrorException(
            "AUTH_GOOGLE_LINK_REQUIRES_PASSWORD",
            "Sign in with your password before linking this Google account.",
            HttpStatus.CONFLICT,
          );
        }
      } else {
        targetUser = await transaction.user.create({
          data: {
            email,
            emailVerifiedAt: new Date(),
            security: { create: {} },
          },
        });
        await this.createAccounts(transaction, targetUser.id);
      }

      await transaction.externalIdentity.create({
        data: {
          userId: targetUser.id,
          provider: "GOOGLE",
          providerSubject: subject,
          providerEmail: email,
        },
      });
      return targetUser;
    });

    if (!user.loginEnabled) {
      throw new ApiErrorException(
        "ACCOUNT_SUSPENDED",
        "This account cannot currently sign in.",
        HttpStatus.FORBIDDEN,
      );
    }
    return this.establishSession(user, body, metadata);
  }

  async login(body: LoginDto, metadata: RequestMetadata) {
    const identifier = body.identifier.trim().toLowerCase();
    const user = await this.prisma.user.findFirst({
      where: identifier.startsWith("+880")
        ? { phone: identifier }
        : { email: identifier },
      include: { security: true },
    });

    if (!user) {
      await this.hasher.verify(await this.dummyHash, body.password);
      this.invalidCredentials();
    }

    const now = new Date();
    if (user.security?.lockedUntil && user.security.lockedUntil > now) {
      this.invalidCredentials();
    }

    const passwordValid = user.passwordHash
      ? await this.hasher.verify(user.passwordHash, body.password)
      : false;
    if (!passwordValid) {
      await this.recordFailedLogin(user.id, metadata);
      this.invalidCredentials();
    }

    if (!user.loginEnabled) {
      throw new ApiErrorException(
        "ACCOUNT_SUSPENDED",
        "This account cannot currently sign in.",
        HttpStatus.FORBIDDEN,
      );
    }

    await this.prisma.userSecurity.upsert({
      where: { userId: user.id },
      create: { userId: user.id },
      update: { failedLoginCount: 0, lockedUntil: null },
    });
    return this.establishSession(user, body, metadata);
  }

  async refresh(refreshToken: string, metadata: RequestMetadata) {
    let payload: RefreshTokenPayload;
    try {
      payload = await this.jwt.verifyAsync<RefreshTokenPayload>(refreshToken, {
        secret: this.refreshSecret,
        issuer,
        audience,
      });
    } catch {
      throw this.sessionExpired();
    }

    if (payload.typ !== "refresh" || !payload.sid || !payload.family) {
      throw this.sessionExpired();
    }

    const session = await this.prisma.userSession.findUnique({
      where: { id: payload.sid },
      include: { user: true },
    });
    if (
      !session ||
      session.userId !== payload.sub ||
      session.tokenFamily !== payload.family ||
      session.revokedAt ||
      session.expiresAt <= new Date()
    ) {
      throw this.sessionExpired();
    }

    if (
      payload.ver !== session.refreshVersion ||
      !(await this.hasher.verify(session.refreshTokenHash, refreshToken))
    ) {
      await this.revokeCompromisedFamily(session.userId, session.tokenFamily);
      throw this.sessionExpired();
    }

    if (!session.user.loginEnabled) {
      await this.revokeFamily(session.tokenFamily);
      throw new ApiErrorException(
        "ACCOUNT_SUSPENDED",
        "This account cannot currently sign in.",
        HttpStatus.FORBIDDEN,
      );
    }

    const nextVersion = session.refreshVersion + 1;
    const tokens = await this.signTokens(
      session.userId,
      session.id,
      session.tokenFamily,
      nextVersion,
    );
    const refreshTokenHash = await this.hasher.hash(tokens.refreshToken);
    const updated = await this.prisma.userSession.updateMany({
      where: {
        id: session.id,
        refreshVersion: session.refreshVersion,
        revokedAt: null,
      },
      data: {
        refreshVersion: nextVersion,
        refreshTokenHash,
        ipAddress: metadata.ipAddress ?? null,
        userAgent: metadata.userAgent ?? null,
        lastSeenAt: new Date(),
        rotatedAt: new Date(),
      },
    });
    if (updated.count !== 1) {
      await this.revokeCompromisedFamily(session.userId, session.tokenFamily);
      throw this.sessionExpired();
    }
    return { data: { ...tokens, user: this.publicUser(session.user) } };
  }

  async validateAccessToken(token: string): Promise<AuthenticatedPrincipal> {
    let payload: { sub: string; sid: string; typ: string };
    try {
      payload = await this.jwt.verifyAsync(token, {
        secret: this.accessSecret,
        issuer,
        audience,
      });
    } catch {
      throw this.sessionExpired();
    }
    if (payload.typ !== "access" || !payload.sub || !payload.sid) {
      throw this.sessionExpired();
    }
    const session = await this.prisma.userSession.findUnique({
      where: { id: payload.sid },
      include: { user: true },
    });
    if (
      !session ||
      session.userId !== payload.sub ||
      session.revokedAt ||
      session.expiresAt <= new Date() ||
      !session.user.loginEnabled
    ) {
      throw this.sessionExpired();
    }
    return { userId: payload.sub, sessionId: payload.sid };
  }

  async logout(principal: AuthenticatedPrincipal) {
    await this.prisma.userSession.updateMany({
      where: {
        id: principal.sessionId,
        userId: principal.userId,
        revokedAt: null,
      },
      data: { revokedAt: new Date() },
    });
    return { data: { loggedOut: true } };
  }

  async logoutAll(userId: string) {
    const result = await this.prisma.userSession.updateMany({
      where: { userId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    return { data: { loggedOut: true, revokedSessions: result.count } };
  }

  async changePassword(
    principal: AuthenticatedPrincipal,
    body: ChangePasswordDto,
  ) {
    const user = await this.prisma.user.findUnique({
      where: { id: principal.userId },
      select: { passwordHash: true },
    });
    if (!user?.passwordHash) {
      throw new ApiErrorException(
        "AUTH_PASSWORD_NOT_SET",
        "This account uses a different sign-in method and has no password to change.",
        HttpStatus.CONFLICT,
      );
    }
    if (!(await this.hasher.verify(user.passwordHash, body.currentPassword))) {
      throw new ApiErrorException(
        "AUTH_INVALID_CURRENT_PASSWORD",
        "The current password is incorrect.",
        HttpStatus.UNAUTHORIZED,
      );
    }
    if (body.currentPassword === body.newPassword) {
      throw new ApiErrorException(
        "AUTH_PASSWORD_UNCHANGED",
        "Choose a different new password.",
        HttpStatus.BAD_REQUEST,
      );
    }
    const passwordHash = await this.hasher.hash(body.newPassword);
    await this.prisma.$transaction(async (tx) => {
      const changed = await tx.user.updateMany({
        where: { id: principal.userId, passwordHash: user.passwordHash },
        data: { passwordHash },
      });
      if (changed.count !== 1) {
        throw new ApiErrorException(
          "AUTH_PASSWORD_CHANGED",
          "The password changed in another session. Please try again.",
          HttpStatus.CONFLICT,
        );
      }
      await tx.userSession.updateMany({
        where: {
          userId: principal.userId,
          id: { not: principal.sessionId },
          revokedAt: null,
        },
        data: { revokedAt: new Date() },
      });
    });
    return { data: { passwordChanged: true, otherSessionsRevoked: true } };
  }

  async listSessions(userId: string) {
    const sessions = await this.prisma.userSession.findMany({
      where: { userId, revokedAt: null, expiresAt: { gt: new Date() } },
      include: { device: true },
      orderBy: { lastSeenAt: "desc" },
    });
    return {
      data: sessions.map((session) => ({
        id: session.id,
        device: session.device
          ? {
              name: session.device.name,
              platform: session.device.platform,
            }
          : null,
        ipAddress: session.ipAddress,
        userAgent: session.userAgent,
        createdAt: session.createdAt,
        lastSeenAt: session.lastSeenAt,
        expiresAt: session.expiresAt,
      })),
    };
  }

  async revokeSession(userId: string, sessionId: string) {
    const result = await this.prisma.userSession.updateMany({
      where: { id: sessionId, userId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    if (result.count !== 1) {
      throw new ApiErrorException(
        "AUTH_SESSION_NOT_FOUND",
        "The session was not found.",
        HttpStatus.NOT_FOUND,
      );
    }
    return { data: { revoked: true } };
  }

  private async establishSession(
    user: { id: string; email: string; phone: string | null },
    device: {
      deviceFingerprint?: string;
      deviceName?: string;
      devicePlatform?: string;
    },
    metadata: RequestMetadata,
  ) {
    const id = randomUUID();
    const tokenFamily = randomUUID();
    const expiresAt = new Date(
      Date.now() + this.refreshTtlDays * 24 * 60 * 60 * 1000,
    );
    let deviceId: string | undefined;
    if (device.deviceFingerprint) {
      const existing = await this.prisma.userDevice.findUnique({
        where: {
          userId_fingerprint: {
            userId: user.id,
            fingerprint: device.deviceFingerprint,
          },
        },
      });
      const knownDeviceCount = existing
        ? 0
        : await this.prisma.userDevice.count({ where: { userId: user.id } });
      const storedDevice = await this.prisma.userDevice.upsert({
        where: {
          userId_fingerprint: {
            userId: user.id,
            fingerprint: device.deviceFingerprint,
          },
        },
        create: {
          userId: user.id,
          fingerprint: device.deviceFingerprint,
          name: device.deviceName ?? null,
          platform: device.devicePlatform ?? null,
        },
        update: {
          name: device.deviceName ?? null,
          platform: device.devicePlatform ?? null,
          lastSeenAt: new Date(),
        },
      });
      deviceId = storedDevice.id;
      if (knownDeviceCount > 0) {
        await this.prisma.riskFlag.create({
          data: {
            userId: user.id,
            type: "UNUSUAL_DEVICE_CHANGE",
            severity: "LOW",
            evidence: { deviceId: storedDevice.id },
          },
        });
      }
    }

    const tokens = await this.signTokens(user.id, id, tokenFamily, 0);
    await this.prisma.userSession.create({
      data: {
        id,
        userId: user.id,
        deviceId: deviceId ?? null,
        tokenFamily,
        refreshTokenHash: await this.hasher.hash(tokens.refreshToken),
        refreshVersion: 0,
        expiresAt,
        ipAddress: metadata.ipAddress ?? null,
        userAgent: metadata.userAgent ?? null,
      },
    });
    return { data: { ...tokens, user: this.publicUser(user) } };
  }

  private async signTokens(
    userId: string,
    sessionId: string,
    family: string,
    version: number,
  ) {
    const [accessToken, refreshToken] = await Promise.all([
      this.jwt.signAsync(
        { sub: userId, sid: sessionId, typ: "access" },
        {
          secret: this.accessSecret,
          expiresIn: this.accessTtlSeconds,
          issuer,
          audience,
        },
      ),
      this.jwt.signAsync(
        { sub: userId, sid: sessionId, family, ver: version, typ: "refresh" },
        {
          secret: this.refreshSecret,
          expiresIn: `${this.refreshTtlDays}d`,
          issuer,
          audience,
        },
      ),
    ]);
    return {
      accessToken,
      refreshToken,
      tokenType: "Bearer",
      accessTokenExpiresIn: this.accessTtlSeconds,
    };
  }

  private demoInitialBalance(): Prisma.Decimal {
    try {
      const configured = new Prisma.Decimal(
        this.config.get<string>("DEMO_INITIAL_BALANCE_BDT") ?? "100000.00",
      );
      if (configured.isPositive()) return configured;
    } catch {
      // Invalid runtime configuration fails back to the documented demo value.
    }
    return new Prisma.Decimal("100000.00");
  }

  private async createAccounts(
    transaction: Prisma.TransactionClient,
    userId: string,
  ): Promise<void> {
    await transaction.currency.upsert({
      where: { code: "BDT" },
      create: { code: "BDT", name: "Bangladeshi Taka", precision: 2 },
      update: {},
    });
    const demoAccount = await transaction.account.create({
      data: { userId, mode: "DEMO" },
    });
    const realAccount = await transaction.account.create({
      data: { userId, mode: "REAL" },
    });
    const demoBalance = this.demoInitialBalance();
    await transaction.wallet.createMany({
      data: [
        {
          accountId: demoAccount.id,
          currencyCode: "BDT",
          availableProjection: demoBalance,
        },
        {
          accountId: realAccount.id,
          currencyCode: "BDT",
          availableProjection: new Prisma.Decimal(0),
        },
      ],
    });
    const ledgerAccounts = await this.ledger.ensureAccountLedgerAccounts(
      transaction,
      demoAccount.id,
      "DEMO",
    );
    await this.ledger.post(transaction, {
      type: "DEMO_FUNDING",
      idempotencyKey: `demo-funding:${userId}`,
      description: "Initial non-withdrawable demo funds",
      entries: [
        {
          ledgerAccountId: ledgerAccounts.control,
          direction: "DEBIT",
          amount: demoBalance,
        },
        {
          ledgerAccountId: ledgerAccounts.available,
          direction: "CREDIT",
          amount: demoBalance,
        },
      ],
    });
  }

  private async recordFailedLogin(userId: string, metadata: RequestMetadata) {
    const maxAttempts = Number(this.config.get("AUTH_MAX_FAILED_LOGINS") ?? 5);
    const current = await this.prisma.userSecurity.upsert({
      where: { userId },
      create: { userId, failedLoginCount: 1 },
      update: { failedLoginCount: { increment: 1 } },
    });
    if (current.failedLoginCount >= maxAttempts) {
      const lockedUntil = new Date(
        Date.now() +
          Number(this.config.get("AUTH_LOCKOUT_MINUTES") ?? 15) * 60_000,
      );
      await this.prisma.$transaction([
        this.prisma.userSecurity.update({
          where: { userId },
          data: { lockedUntil },
        }),
        this.prisma.riskFlag.create({
          data: {
            userId,
            type: "REPEATED_FAILED_LOGIN",
            severity: "MEDIUM",
            evidence: {
              failedLoginCount: current.failedLoginCount,
              ipAddress: metadata.ipAddress ?? null,
            },
          },
        }),
      ]);
    }
  }

  private async revokeCompromisedFamily(userId: string, family: string) {
    await this.prisma.$transaction([
      this.prisma.userSession.updateMany({
        where: { tokenFamily: family, revokedAt: null },
        data: { revokedAt: new Date() },
      }),
      this.prisma.riskFlag.create({
        data: {
          userId,
          type: "REFRESH_TOKEN_REUSE",
          severity: "HIGH",
          evidence: { tokenFamily: family },
        },
      }),
    ]);
  }

  private async revokeFamily(family: string): Promise<void> {
    await this.prisma.userSession.updateMany({
      where: { tokenFamily: family, revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }

  private invalidCredentials(): never {
    throw new ApiErrorException(
      "AUTH_INVALID_CREDENTIALS",
      "The email, phone, or password is incorrect.",
      HttpStatus.UNAUTHORIZED,
    );
  }

  private sessionExpired(): ApiErrorException {
    return new ApiErrorException(
      "AUTH_SESSION_EXPIRED",
      "Your session has expired. Please sign in again.",
      HttpStatus.UNAUTHORIZED,
    );
  }

  private publicUser(user: {
    id: string;
    email: string;
    phone: string | null;
  }) {
    return { id: user.id, email: user.email, phone: user.phone };
  }

  private get googleWebClientId(): string {
    const value = String(this.config.get("GOOGLE_WEB_CLIENT_ID") ?? "").trim();
    if (!value) {
      throw new ApiErrorException(
        "GOOGLE_AUTH_NOT_CONFIGURED",
        "Google sign-in is not configured on this server.",
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
    return value;
  }

  private get accessSecret(): string {
    return String(this.config.get("JWT_ACCESS_SECRET"));
  }

  private get refreshSecret(): string {
    return String(this.config.get("JWT_REFRESH_SECRET"));
  }

  private get accessTtlSeconds(): number {
    return Number(this.config.get("JWT_ACCESS_TTL_SECONDS") ?? 900);
  }

  private get refreshTtlDays(): number {
    return Number(this.config.get("JWT_REFRESH_TTL_DAYS") ?? 30);
  }
}
