/* eslint-disable @typescript-eslint/no-unsafe-argument, @typescript-eslint/no-unsafe-assignment, @typescript-eslint/no-unsafe-member-access */
import { ConfigService } from "@nestjs/config";
import { JwtService } from "@nestjs/jwt";
import { validate } from "class-validator";
import { describe, expect, it, vi } from "vitest";
import { AuthService } from "../src/auth/auth.service";
import { RegisterDto } from "../src/auth/dto/register.dto";
import { ChangePasswordDto } from "../src/auth/dto/change-password.dto";
import { PasswordHasherService } from "../src/auth/password-hasher.service";
import type { PrismaService } from "../src/database/prisma.service";
import { ApiErrorException } from "../src/http/api-error";
import { LedgerService } from "../src/database/ledger.service";

const user = {
  id: "00000000-0000-4000-8000-000000000001",
  email: "user@example.com",
  phone: "+8801712345678",
  loginEnabled: true,
};

function config(): ConfigService {
  return new ConfigService({
    JWT_ACCESS_SECRET: "test-access-secret-with-at-least-32-characters",
    JWT_REFRESH_SECRET: "test-refresh-secret-with-at-least-32-characters",
    JWT_ACCESS_TTL_SECONDS: "900",
    JWT_REFRESH_TTL_DAYS: "30",
  });
}

function prismaMock(session: Record<string, unknown>) {
  const userSession = {
    findUnique: vi.fn().mockResolvedValue(session),
    updateMany: vi.fn().mockResolvedValue({ count: 1 }),
  };
  const riskFlag = { create: vi.fn().mockResolvedValue({}) };
  const prisma = {
    userSession,
    riskFlag,
    $transaction: vi.fn(async (operations: Promise<unknown>[]) =>
      Promise.all(operations),
    ),
  };
  return { prisma: prisma as unknown as PrismaService, userSession, riskFlag };
}

describe("authentication security", () => {
  it("validates password changes and revokes other sessions only after updating the hash", async () => {
    const invalid = Object.assign(new ChangePasswordDto(), {
      currentPassword: "old",
      newPassword: "weak",
    });
    expect((await validate(invalid)).map((error) => error.property)).toEqual([
      "newPassword",
    ]);
    const change = Object.assign(new ChangePasswordDto(), {
      currentPassword: "OldPassword!123",
      newPassword: "NewPassword!123",
    });
    expect(await validate(change)).toEqual([]);
    const updateMany = vi.fn().mockResolvedValue({ count: 1 });
    const revokeOthers = vi.fn().mockResolvedValue({ count: 2 });
    const prisma = {
      user: { findUnique: vi.fn().mockResolvedValue({ passwordHash: "old-hash" }) },
      $transaction: vi.fn(async (work: (tx: unknown) => Promise<unknown>) =>
        work({ user: { updateMany }, userSession: { updateMany: revokeOthers } }),
      ),
    } as unknown as PrismaService;
    const hasher = {
      hash: vi.fn().mockResolvedValue("new-hash"),
      verify: vi.fn().mockResolvedValue(true),
    } as unknown as PasswordHasherService;
    const service = new AuthService(
      prisma,
      new JwtService(),
      config(),
      hasher,
      {} as LedgerService,
    );
    const principal = { userId: user.id, sessionId: "current-session" };
    await expect(service.changePassword(principal, change)).resolves.toEqual({
      data: { passwordChanged: true, otherSessionsRevoked: true },
    });
    expect(updateMany).toHaveBeenCalledWith({
      where: { id: user.id, passwordHash: "old-hash" },
      data: { passwordHash: "new-hash" },
    });
    expect(revokeOthers).toHaveBeenCalledWith({
      where: {
        userId: user.id,
        id: { not: "current-session" },
        revokedAt: null,
      },
      data: { revokedAt: expect.any(Date) },
    });
  });
  it("uses Argon2id and never needs the plaintext to verify later", async () => {
    const hasher = new PasswordHasherService();
    const hash = await hasher.hash("StrongPassword!123");
    expect(hash).toMatch(/^\$argon2id\$/);
    expect(hash).not.toContain("StrongPassword!123");
    await expect(hasher.verify(hash, "StrongPassword!123")).resolves.toBe(true);
    await expect(hasher.verify(hash, "wrong-password")).resolves.toBe(false);
  });

  it("requires only a valid email and strong password for registration", async () => {
    const dto = Object.assign(new RegisterDto(), {
      email: "not-an-email",
      password: "weak",
    });
    const errors = await validate(dto);
    expect(errors.map((error) => error.property).sort()).toEqual([
      "email",
      "password",
    ]);

    const minimal = Object.assign(new RegisterDto(), {
      email: "new-user@example.com",
      password: "StrongPassword!123",
    });
    await expect(validate(minimal)).resolves.toEqual([]);
  });

  it("rotates refresh tokens with a new Argon2id hash and version", async () => {
    const jwt = new JwtService();
    const hasher = new PasswordHasherService();
    const family = "00000000-0000-4000-8000-000000000002";
    const sessionId = "00000000-0000-4000-8000-000000000003";
    const refreshToken = await jwt.signAsync(
      { sub: user.id, sid: sessionId, family, ver: 0, typ: "refresh" },
      {
        secret: String(config().get("JWT_REFRESH_SECRET")),
        issuer: "primevest-api",
        audience: "primevest-mobile",
        expiresIn: "30d",
      },
    );
    const session = {
      id: sessionId,
      userId: user.id,
      tokenFamily: family,
      refreshVersion: 0,
      refreshTokenHash: await hasher.hash(refreshToken),
      revokedAt: null,
      expiresAt: new Date(Date.now() + 60_000),
      user,
    };
    const fake = prismaMock(session);
    const service = new AuthService(
      fake.prisma,
      jwt,
      config(),
      hasher,
      new LedgerService(),
    );

    const result = await service.refresh(refreshToken, {
      ipAddress: "127.0.0.1",
      userAgent: "test",
    });

    expect(result.data.refreshToken).not.toBe(refreshToken);
    const update = fake.userSession.updateMany.mock.calls[0]?.[0];
    expect(update.data.refreshVersion).toBe(1);
    expect(update.data.refreshTokenHash).not.toBe(result.data.refreshToken);
    await expect(
      hasher.verify(update.data.refreshTokenHash, result.data.refreshToken),
    ).resolves.toBe(true);
  });

  it("revokes a token family and creates a risk flag on refresh replay", async () => {
    const jwt = new JwtService();
    const hasher = new PasswordHasherService();
    const family = "00000000-0000-4000-8000-000000000004";
    const sessionId = "00000000-0000-4000-8000-000000000005";
    const replayedToken = await jwt.signAsync(
      { sub: user.id, sid: sessionId, family, ver: 0, typ: "refresh" },
      {
        secret: String(config().get("JWT_REFRESH_SECRET")),
        issuer: "primevest-api",
        audience: "primevest-mobile",
        expiresIn: "30d",
      },
    );
    const fake = prismaMock({
      id: sessionId,
      userId: user.id,
      tokenFamily: family,
      refreshVersion: 1,
      refreshTokenHash: await hasher.hash("new-token"),
      revokedAt: null,
      expiresAt: new Date(Date.now() + 60_000),
      user,
    });
    const service = new AuthService(
      fake.prisma,
      jwt,
      config(),
      hasher,
      new LedgerService(),
    );

    await expect(service.refresh(replayedToken, {})).rejects.toMatchObject({
      code: "AUTH_SESSION_EXPIRED",
    } satisfies Partial<ApiErrorException>);
    expect(fake.userSession.updateMany).toHaveBeenCalledWith({
      where: { tokenFamily: family, revokedAt: null },
      data: { revokedAt: expect.any(Date) },
    });
    expect(fake.riskFlag.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        userId: user.id,
        type: "REFRESH_TOKEN_REUSE",
        severity: "HIGH",
      }),
    });
  });
});
