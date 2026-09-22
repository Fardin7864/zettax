import { ConfigService } from "@nestjs/config";
import { Prisma } from "@prisma/client";
import { plainToInstance } from "class-transformer";
import { validate } from "class-validator";
import { describe, expect, it, vi } from "vitest";
import { AccountModeParamDto } from "../src/accounts/accounts.dto";
import { AccountsService } from "../src/accounts/accounts.service";
import { requireIdempotencyKey } from "../src/accounts/accounts.validation";
import type { IdempotencyService } from "../src/database/idempotency.service";
import type { LedgerService } from "../src/database/ledger.service";
import type { OutboxService } from "../src/database/outbox.service";
import type { PrismaService } from "../src/database/prisma.service";

function accountsService(prisma: object): AccountsService {
  return new AccountsService(
    prisma as PrismaService,
    new ConfigService(),
    {} as LedgerService,
    {} as IdempotencyService,
    {} as OutboxService,
  );
}

describe("authenticated account contract", () => {
  it("normalizes an account mode path value and rejects unknown modes", async () => {
    const demo = plainToInstance(AccountModeParamDto, { mode: "demo" });
    expect(await validate(demo)).toHaveLength(0);
    expect(demo.mode).toBe("DEMO");

    const invalid = plainToInstance(AccountModeParamDto, { mode: "paper" });
    expect(await validate(invalid)).not.toHaveLength(0);
  });

  it("requires a bounded safe idempotency key for demo reset", () => {
    expect(requireIdempotencyKey("demo-reset:device-123")).toBe(
      "demo-reset:device-123",
    );
    expect(() => requireIdempotencyKey("short")).toThrow();
    try {
      requireIdempotencyKey("short");
    } catch (error: unknown) {
      expect(error).toMatchObject({ code: "IDEMPOTENCY_KEY_INVALID" });
    }
  });

  it("serializes wallet money as decimal strings", async () => {
    const findMany = vi.fn().mockResolvedValue([
      {
        id: "account-id",
        mode: "DEMO",
        status: "ACTIVE",
        createdAt: new Date("2026-09-09T00:00:00.000Z"),
        wallets: [
          {
            currencyCode: "BDT",
            availableProjection: new Prisma.Decimal("99999.10"),
            lockedProjection: new Prisma.Decimal("0.90"),
          },
        ],
        _count: { positions: 2 },
      },
    ]);

    const result = await accountsService({ account: { findMany } }).list(
      "user-id",
    );

    expect(findMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { userId: "user-id" } }),
    );
    expect(result[0]).toMatchObject({
      mode: "DEMO",
      openPositionCount: 2,
      wallets: [
        {
          currencyCode: "BDT",
          available: "99999.10",
          locked: "0.90",
          equity: "100000.00",
        },
      ],
    });
  });

  it("rejects malformed opaque transaction cursors", async () => {
    const service = accountsService({
      account: {
        findUnique: vi.fn().mockResolvedValue({ id: "account-id" }),
      },
    });
    await expect(
      service.transactions("user-id", "DEMO", 30, "not-a-cursor"),
    ).rejects.toMatchObject({ code: "PAGINATION_CURSOR_INVALID" });
  });
});
