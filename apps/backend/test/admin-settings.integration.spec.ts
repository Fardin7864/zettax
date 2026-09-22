import { ValidationPipe, type INestApplication } from "@nestjs/common";
import { ConfigModule } from "@nestjs/config";
import { Test } from "@nestjs/testing";
import { randomUUID } from "node:crypto";
import { createRequire } from "node:module";
import * as argon2 from "argon2";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { PrismaService } from "../src/database/prisma.service";
const suite =
  process.env.RUN_DATABASE_INTEGRATION === "true" ? describe : describe.skip;
suite("administrator operations HTTP controls", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let sessions: import("../src/admin/admin.module").AdminSession;
  let maker: string;
  let checker: string;
  let makerToken: string;
  let checkerToken: string;
  const email = `admin-test-${randomUUID()}@example.invalid`,
    password = randomUUID();
  const base = "http://127.0.0.1:3002/admin";
  async function call(
    path: string,
    token = makerToken,
    body?: unknown,
    method = body ? "POST" : "GET",
  ) {
    return fetch(`${base}/${path}`, {
      method,
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
  }
  beforeAll(async () => {
    const runtimeRequire = createRequire(`${process.cwd()}/package.json`);
    const { AdminModule, AdminSession } = runtimeRequire(
      "./dist/apps/backend/src/admin/admin.module.js",
    ) as typeof import("../src/admin/admin.module");
    const { DatabaseModule } = runtimeRequire(
      "./dist/apps/backend/src/database/database.module.js",
    ) as typeof import("../src/database/database.module");
    const { PrismaService: RuntimePrisma } = runtimeRequire(
      "./dist/apps/backend/src/database/prisma.service.js",
    ) as typeof import("../src/database/prisma.service");
    const { ChangesModule } = runtimeRequire(
      "./dist/apps/backend/src/operations/changes.module.js",
    ) as typeof import("../src/operations/changes.module");
    const { OperationsModule } = runtimeRequire(
      "./dist/apps/backend/src/operations/operations.module.js",
    ) as typeof import("../src/operations/operations.module");
    const { SecurityModule } = runtimeRequire(
      "./dist/apps/backend/src/admin/security.module.js",
    ) as typeof import("../src/admin/security.module");
    const module = await Test.createTestingModule({
      imports: [
        ConfigModule.forRoot({
          isGlobal: true,
          ignoreEnvFile: true,
          load: [
            () => ({
              JWT_ACCESS_SECRET: "admin-http-test-only-secret",
              RELEASE_VERSION: `test-${randomUUID()}`,
            }),
          ],
        }),
        DatabaseModule,
        AdminModule,
        ChangesModule,
        OperationsModule,
        SecurityModule,
      ],
    }).compile();
    app = module.createNestApplication({ logger: false });
    const { RequestIdMiddleware } = runtimeRequire(
      "./dist/apps/backend/src/http/request-id.middleware.js",
    ) as typeof import("../src/http/request-id.middleware");
    const middleware = new RequestIdMiddleware();
    app.use(middleware.use.bind(middleware));
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
      }),
    );
    prisma = module.get(RuntimePrisma);
    sessions = module.get(AdminSession);
    const role = await prisma.role.findUniqueOrThrow({
      where: { name: "operations" },
    });
    maker = (
      await prisma.adminUser.create({
        data: {
          email,
          passwordHash: await argon2.hash(password),
          assignments: { create: { roleId: role.id } },
        },
      })
    ).id;
    checker = (
      await prisma.adminUser.create({
        data: {
          email: `checker-${randomUUID()}@example.invalid`,
          passwordHash: "test-not-login",
          assignments: { create: { roleId: role.id } },
        },
      })
    ).id;
    // Explicit test-only session issuance exercises authorization after WebAuthn;
    // it does not bypass or add a production enrollment endpoint.
    makerToken = await sessions.sign(maker, Date.now() + 300000);
    checkerToken = await sessions.sign(checker, Date.now() + 300000);
    await app.listen(3002, "127.0.0.1");
  }, 60000);
  afterAll(async () => {
    if (prisma) {
      await prisma.systemConfig.upsert({
        where: { key: "trading.profitFeeRate" },
        create: { key: "trading.profitFeeRate", value: "0" },
        update: { value: "0" },
      });
      await prisma.adminUser.updateMany({
        where: { id: { in: [maker, checker].filter(Boolean) } },
        data: { active: false },
      });
    }
    if (app) await app.close();
  });
  it("requires login and step-up; direct single-operator PATCH is removed", async () => {
    expect((await call("trading-settings", "")).status).toBe(401);
    const login = await call("auth/login", "", { email, password });
    expect(login.status).toBe(201);
    const { accessToken } = (await login.json()) as { accessToken: string };
    expect((await call("trading-settings", accessToken)).status).toBe(200);
    expect(
      (
        await call("changes", accessToken, {
          kind: "TRADING_FEE",
          targetId: "fee",
          payload: { rate: "0.1" },
        })
      ).status,
    ).toBe(403);
    expect(
      (await call("trading-settings", makerToken, { rate: "0.1" }, "PATCH"))
        .status,
    ).toBe(404);
    expect(
      (await call("auth/security-options", accessToken, { kind: "VERIFY" }))
        .status,
    ).toBe(403);
    const challenge = await call("auth/security-options", accessToken, {
      kind: "REGISTER",
    });
    expect(challenge.status).toBe(201);
    const invalid = await call("auth/security-verify", accessToken, {
      kind: "REGISTER",
      challengeId: randomUUID(),
      response: {},
    });
    expect(invalid.status).toBe(400);
  });
  it("validates fees, blocks self-approval, and audits independently approved changes", async () => {
    const login = await call("auth/login", "", { email, password });
    const session = (await login.json()) as { accessToken: string };
    expect(
      (
        await call("auth/confirm-password", session.accessToken, {
          password: "incorrect",
        })
      ).status,
    ).toBe(403);
    const confirmed = await call("auth/confirm-password", session.accessToken, {
      password,
    });
    expect(confirmed.status).toBe(201);
    makerToken = ((await confirmed.json()) as { accessToken: string })
      .accessToken;
    expect(
      (
        await call("changes", makerToken, {
          kind: "TRADING_FEE",
          targetId: "fee",
          payload: { rate: "1.01" },
        })
      ).status,
    ).toBe(400);
    const result = await call("changes", makerToken, {
      kind: "TRADING_FEE",
      targetId: "fee",
      payload: { rate: "0.1" },
    });
    expect(result.status).toBe(201);
    const row = (await result.json()) as { id: string };
    expect(
      (
        await call(`changes/${row.id}/review`, makerToken, {
          decision: "APPROVED",
        })
      ).status,
    ).toBe(403);
    expect(
      (
        await call(`changes/${row.id}/review`, checkerToken, {
          decision: "APPROVED",
        })
      ).status,
    ).toBe(201);
    expect(
      (
        await prisma.systemConfig.findUniqueOrThrow({
          where: { key: "trading.profitFeeRate" },
        })
      ).value,
    ).toBe("0.1");
    expect(await prisma.auditLog.count({ where: { resourceId: row.id } })).toBe(
      2,
    );
    expect(
      (
        await call(`changes/${row.id}/review`, checkerToken, {
          decision: "APPROVED",
        })
      ).status,
    ).toBe(403);
  });
  it("blocks stale proposals while still allowing their rejection", async () => {
    const proposal = await call("changes", makerToken, {
      kind: "TRADING_FEE",
      targetId: "fee",
      payload: { rate: "0.2" },
    });
    const row = (await proposal.json()) as { id: string };
    await prisma.systemConfig.update({
      where: { key: "trading.profitFeeRate" },
      data: { value: "0.3" },
    });
    expect(
      (
        await call(`changes/${row.id}/review`, checkerToken, {
          decision: "APPROVED",
        })
      ).status,
    ).toBe(409);
    expect(
      (
        await call(`changes/${row.id}/review`, checkerToken, {
          decision: "REJECTED",
        })
      ).status,
    ).toBe(201);
  });
  it("requires clean evidence and independent treasury review, never fabricated backing", async () => {
    expect(
      (
        await call("treasury", makerToken, {
          accountReference: "BANK-TEST",
          category: "RESERVE",
          balance: "1000",
          asOf: new Date().toISOString(),
          evidenceId: randomUUID(),
          notes: "Test statement only",
        })
      ).status,
    ).toBe(400);
    const evidence = await prisma.evidenceFile.create({
      data: {
        ownerId: maker,
        ownerType: "ADMIN",
        purpose: "TREASURY",
        objectKey: `test/${randomUUID()}`,
        filename: "test.png",
        mimeType: "image/png",
        sha256: "test",
        sizeBytes: 1,
      },
    });
    const result = await call("treasury", makerToken, {
      accountReference: `test-${randomUUID()}`,
      category: "RESERVE",
      balance: "1000",
      asOf: new Date().toISOString(),
      evidenceId: evidence.id,
      notes: "Isolated database fixture, not real money",
    });
    expect(result.status).toBe(201);
    const row = (await result.json()) as { id: string };
    expect(
      (
        await call(`treasury/${row.id}/review`, makerToken, {
          decision: "APPROVED",
        })
      ).status,
    ).toBe(403);
    expect(
      (
        await call(`treasury/${row.id}/review`, checkerToken, {
          decision: "APPROVED",
        })
      ).status,
    ).toBe(201);
    await expect(
      prisma.treasuryStatement.update({
        where: { id: row.id },
        data: { balance: "999999" },
      }),
    ).rejects.toThrow();
    const release = (await (await call("release")).json()) as {
      ready: boolean;
      missing: string[];
    };
    expect(release.ready).toBe(false);
    expect(release.missing.length).toBe(11);
    expect(
      (
        await call("release/approve", makerToken, {
          gate: "LEGAL",
          evidenceId: evidence.id,
          expiresAt: new Date(Date.now() + 86400000).toISOString(),
          notes: "Cannot assume legal authority from operations role",
        })
      ).status,
    ).toBe(403);
  });
  it("records an authorized gate, invalidates revoked authority, and preserves revoked evidence", async () => {
    const role = await prisma.role.findUniqueOrThrow({
      where: { name: "release-legal" },
    });
    await prisma.adminRoleAssignment.create({
      data: { adminUserId: maker, roleId: role.id },
    });
    const evidence = await prisma.evidenceFile.create({
      data: {
        ownerId: maker,
        ownerType: "ADMIN",
        purpose: "RELEASE",
        objectKey: `test/${randomUUID()}`,
        filename: "fixture.png",
        mimeType: "image/png",
        sha256: "fixture",
        sizeBytes: 1,
      },
    });
    const result = await call("release/approve", makerToken, {
      gate: "LEGAL",
      evidenceId: evidence.id,
      expiresAt: new Date(Date.now() + 86400000).toISOString(),
      notes: "Isolated test sign-off; no production authority is asserted",
    });
    expect(result.status).toBe(201);
    const row = (await result.json()) as { id: string };
    let state = (await (await call("release")).json()) as { missing: string[] };
    expect(state.missing).not.toContain("LEGAL");
    await prisma.adminRoleAssignment.delete({
      where: { adminUserId_roleId: { adminUserId: maker, roleId: role.id } },
    });
    state = (await (await call("release")).json()) as { missing: string[] };
    expect(state.missing).toContain("LEGAL");
    await prisma.adminRoleAssignment.create({
      data: { adminUserId: maker, roleId: role.id },
    });
    expect(
      (await call(`release/${row.id}/revoke`, makerToken, {})).status,
    ).toBe(201);
    state = (await (await call("release")).json()) as { missing: string[] };
    expect(state.missing).toContain("LEGAL");
    await expect(
      prisma.releaseApproval.update({
        where: { id: row.id },
        data: { notes: "rewritten" },
      }),
    ).rejects.toThrow();
  });
  it("supports audited office-held legal records but not substitute treasury evidence", async () => {
    const body = {
      gate: "LEGAL",
      officeReference:
        "Office file LEG-2026-001; legal custodian; approved scope recorded in notes",
      notes: "Isolated fixture only: product and jurisdiction scope",
      expiresAt: new Date(Date.now() + 86400000).toISOString(),
    };
    expect((await call("release/approve", makerToken, body)).status).toBe(201);
    const state = (await (await call("release")).json()) as {
      missing: string[];
      ready: boolean;
    };
    expect(state.missing).not.toContain("LEGAL");
    expect(state.ready).toBe(false);
    const role = await prisma.role.findUniqueOrThrow({
      where: { name: "release-treasury" },
    });
    await prisma.adminRoleAssignment.create({
      data: { adminUserId: maker, roleId: role.id },
    });
    expect(
      (await call("release/approve", makerToken, { ...body, gate: "TREASURY" }))
        .status,
    ).toBe(400);
  });
  it("locks repeated failed password confirmations and rejects expired step-up", async () => {
    const expired = await sessions.sign(checker, Date.now() - 1000);
    expect(
      (
        await call("changes", expired, {
          kind: "TRADING_FEE",
          targetId: "fee",
          payload: { rate: "0.1" },
        })
      ).status,
    ).toBe(403);
    // Maker already has one failed confirmation from the earlier test.
    for (let i = 0; i < 4; i++)
      expect(
        (await call("auth/confirm-password", makerToken, { password: "wrong" }))
          .status,
      ).toBe(403);
    expect(
      (await call("auth/confirm-password", makerToken, { password })).status,
    ).toBe(429);
  });
  it("serves every records area without exposing password hashes", async () => {
    for (const area of [
      "users",
      "kyc",
      "contracts",
      "markets",
      "ledger",
      "risk",
      "audit",
      "admins",
      "roles",
    ]) {
      const response = await call(`records/${area}`);
      expect(response.status, area).toBe(200);
      expect(await response.text()).not.toContain("passwordHash");
    }
  });
  it("rechecks revoked privileges and inactive administrators", async () => {
    await prisma.adminRoleAssignment.deleteMany({
      where: { adminUserId: maker },
    });
    expect((await call("trading-settings")).status).toBe(403);
    await prisma.adminUser.update({
      where: { id: maker },
      data: { active: false },
    });
    expect((await call("trading-settings")).status).toBe(401);
  });
});
