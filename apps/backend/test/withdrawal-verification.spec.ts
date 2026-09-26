import { describe, expect, it } from "vitest";
import { encodeBase32, totp, VerificationService } from "../src/verification/verification.service";

describe("withdrawal authenticator verification", () => {
  it("matches the RFC 6238 SHA-1 test vector", () => {
    const secret = encodeBase32(Buffer.from("12345678901234567890"));
    expect(secret).toBe("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ");
    expect(totp(secret, 1)).toBe("287082");
  });

  it("requires enrollment and rejects a reused code", async () => {
    const priorKey = process.env.MFA_ENCRYPTION_KEY;
    process.env.MFA_ENCRYPTION_KEY = "a".repeat(64);
    const row: Record<string, unknown> = { userId: "user", totpEnabled: false, pendingTotpSecret: null, encryptedTotpSecret: null, lastTotpCounter: null };
    const security = {
      findUnique: async () => ({ ...row }),
      upsert: async ({ create, update }: { create: Record<string, unknown>; update: Record<string, unknown> }) => Object.assign(row, row.pendingTotpSecret ? update : create),
      update: async ({ data }: { data: Record<string, unknown> }) => Object.assign(row, data),
      updateMany: async ({ where, data }: { where: { OR: [{ lastTotpCounter: null }, { lastTotpCounter: { lt: bigint } }] }; data: { lastTotpCounter: bigint } }) => {
        const last = row.lastTotpCounter as bigint | null;
        if (last !== null && last >= where.OR[1].lastTotpCounter.lt) return { count: 0 };
        Object.assign(row, data);
        return { count: 1 };
      },
    };
    const prisma = { userSecurity: security, user: { findUniqueOrThrow: async () => ({ email: "test@example.com" }) } };
    try {
      const service = new VerificationService(prisma as never);
      const setup = await service.beginAuthenticator("user");
      const code = totp(setup.secret, Math.floor(Date.now() / 30_000));
      await expect(service.verifyWithdrawal({ userSecurity: security } as never, "user", "AUTHENTICATOR", code)).rejects.toMatchObject({ code: "VERIFICATION_FAILED" });
      await service.confirmAuthenticator("user", code);
      await expect(service.verifyWithdrawal({ userSecurity: security } as never, "user", "AUTHENTICATOR", code)).rejects.toMatchObject({ code: "VERIFICATION_FAILED" });
      row.lastTotpCounter = -1n;
      await service.verifyWithdrawal({ userSecurity: security } as never, "user", "AUTHENTICATOR", code);
      await expect(service.verifyWithdrawal({ userSecurity: security } as never, "user", "AUTHENTICATOR", code)).rejects.toMatchObject({ code: "VERIFICATION_FAILED" });
    } finally {
      if (priorKey === undefined) delete process.env.MFA_ENCRYPTION_KEY;
      else process.env.MFA_ENCRYPTION_KEY = priorKey;
    }
  });
});
