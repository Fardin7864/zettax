import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createHmac } from "node:crypto";
import { VerificationService } from "../src/verification/verification.service";

const mail = vi.hoisted(() => ({ sendMail: vi.fn() }));
vi.mock("nodemailer", () => ({ default: { createTransport: () => mail } }));

function fixture() {
  const row: Record<string, unknown> = { userId: "user", emailEnabled: false, totpEnabled: false, emailCodeAttempts: 0 };
  const security = {
    findUnique: async () => ({ ...row }),
    upsert: async ({ update }: { update: Record<string, unknown> }) => Object.assign(row, update),
    update: async ({ data }: { data: Record<string, unknown> }) => Object.assign(row, data),
    updateMany: async ({ where, data }: { where: Record<string, unknown>; data: Record<string, unknown> }) => {
      if (where.emailCodeHash !== row.emailCodeHash) return { count: 0 };
      if (data.emailCodeAttempts && typeof data.emailCodeAttempts === "object") row.emailCodeAttempts = Number(row.emailCodeAttempts) + 1;
      else Object.assign(row, data);
      return { count: 1 };
    },
  };
  const tx = { userSecurity: security };
  const prisma = { ...tx, user: { findUnique: async () => ({ email: "user@example.com" }), findUniqueOrThrow: async () => ({ email: "user@example.com" }) }, $transaction: async (operation: (client: typeof tx) => Promise<unknown>) => operation(tx) };
  return { row, tx, service: new VerificationService(prisma as never) };
}
function mailedCode() { return (mail.sendMail.mock.calls.at(-1)![0] as { text: string }).text.match(/code is (\d{6})/)![1]!; }

describe("email two-factor verification", () => {
  beforeEach(() => {
    vi.stubEnv("MFA_ENCRYPTION_KEY", "a".repeat(64));
    vi.stubEnv("SMTP_HOST", "smtp.test.invalid");
    vi.stubEnv("SMTP_USER", "sender@example.com");
    vi.stubEnv("SMTP_PASSWORD", "test-only");
    mail.sendMail.mockReset().mockResolvedValue({});
  });
  afterEach(() => vi.unstubAllEnvs());
  it("enrolls only after proof of mailbox ownership and never stores the plaintext code", async () => {
    const { service, row } = fixture();
    await service.sendEmailCode("user", "ENROLLMENT");
    const code = mailedCode();
    expect(row.emailEnabled).toBe(false);
    expect(row.emailCodeHash).toBe(createHmac("sha256", Buffer.from("a".repeat(64), "hex")).update(`user:${code}`).digest("hex"));
    await service.confirmEmail("user", code);
    expect(row.emailEnabled).toBe(true);
    expect(row.emailCodeHash).toBeNull();
    expect((await service.status("user")).emailEnabled).toBe(true);
    await expect(service.confirmEmail("user", code)).rejects.toMatchObject({ code: "VERIFICATION_FAILED" });
  });
  it("rejects withdrawals without enrollment and rejects enrollment codes for withdrawals", async () => {
    const { service, tx, row } = fixture();
    await expect(service.sendEmailCode("user")).rejects.toMatchObject({ code: "FACTOR_NOT_ENABLED" });
    await service.sendEmailCode("user", "ENROLLMENT");
    row.emailEnabled = true;
    await expect(service.verifyWithdrawal(tx as never, "user", "EMAIL", mailedCode())).rejects.toMatchObject({ code: "VERIFICATION_FAILED" });
  });
  it("withdrawal codes are one-use and cannot be used to enroll", async () => {
    const { service, tx, row } = fixture();
    row.emailEnabled = true;
    await service.sendEmailCode("user");
    const code = mailedCode();
    await expect(service.confirmEmail("user", code)).rejects.toMatchObject({ code: "VERIFICATION_FAILED" });
    await service.verifyWithdrawal(tx as never, "user", "EMAIL", code);
    await expect(service.verifyWithdrawal(tx as never, "user", "EMAIL", code)).rejects.toMatchObject({ code: "VERIFICATION_FAILED" });
  });
  it("expires codes and persists a five-attempt lockout", async () => {
    const { service, tx, row } = fixture();
    row.emailEnabled = true;
    await service.sendEmailCode("user");
    const code = mailedCode();
    const wrong = code === "000000" ? "111111" : "000000";
    for (let i = 0; i < 5; i++) await expect(service.verifyWithdrawal(tx as never, "user", "EMAIL", wrong)).rejects.toMatchObject({ code: "VERIFICATION_FAILED" });
    expect(row.emailCodeAttempts).toBe(5);
    await expect(service.verifyWithdrawal(tx as never, "user", "EMAIL", code)).rejects.toMatchObject({ code: "VERIFICATION_FAILED" });
    row.emailCodeAttempts = 0;
    row.emailCodeExpiresAt = new Date(Date.now() - 1);
    await expect(service.verifyWithdrawal(tx as never, "user", "EMAIL", code)).rejects.toMatchObject({ code: "VERIFICATION_FAILED" });
  });
  it("rate limits resends and clears undelivered codes", async () => {
    const { service, row } = fixture();
    await service.sendEmailCode("user", "ENROLLMENT");
    await expect(service.sendEmailCode("user", "ENROLLMENT")).rejects.toMatchObject({ code: "CODE_RATE_LIMITED" });
    row.emailCodeSentAt = new Date(Date.now() - 61_000);
    mail.sendMail.mockRejectedValueOnce(new Error("delivery failed"));
    await expect(service.sendEmailCode("user", "ENROLLMENT")).rejects.toMatchObject({ code: "EMAIL_DELIVERY_FAILED" });
    expect(row.emailCodeHash).toBeNull();
  });
});
