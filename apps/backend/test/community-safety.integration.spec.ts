import { PrismaClient } from "@prisma/client";
import { randomUUID } from "node:crypto";
import { beforeAll, afterAll, describe, expect, it, vi } from "vitest";
import {
  CommunitySafetyService,
  COMMUNITY_RULES_VERSION,
} from "../src/community/community-safety.service";
import { CommunityService } from "../src/community/community.service";
import type { AdminRequest } from "../src/admin/admin.module";

const suite =
  process.env.RUN_DATABASE_INTEGRATION === "true" ? describe : describe.skip;
suite("community safety with PostgreSQL", () => {
  const prisma = new PrismaClient();
  const safety = new CommunitySafetyService(prisma as never);
  const gateway = {
    created: vi.fn(),
    changed: vi.fn(),
    commentCreated: vi.fn(),
  };
  const community = new CommunityService(
    prisma as never,
    {} as never,
    gateway as never,
    safety,
  );
  let alice: string, bob: string, charlie: string;
  let post: string, comment: string;
  let admin: AdminRequest;
  beforeAll(async () => {
    await prisma.$connect();
    const create = async () =>
      (
        await prisma.user.create({
          data: {
            email: `safety-${randomUUID()}@example.invalid`,
            passwordHash: "not-a-login-hash",
          },
        })
      ).id;
    alice = await create();
    bob = await create();
    charlie = await create();
    const moderator = await prisma.adminUser.create({
      data: {
        email: `moderator-${randomUUID()}@example.invalid`,
        passwordHash: "fixture",
      },
    });
    admin = {
      user: {
        adminId: moderator.id,
        permissions: ["community.moderate"],
        stepUpUntil: Date.now() + 300000,
      },
      requestId: randomUUID(),
    } as AdminRequest;
    await safety.accept(bob, COMMUNITY_RULES_VERSION);
    post = (await community.create(bob, "Fixture post")).id;
    await safety.accept(charlie, COMMUNITY_RULES_VERSION);
    comment = (await community.comment(charlie, post, "Fixture reply")).id;
  });
  afterAll(() => prisma.$disconnect());
  it("requires explicit current rules acceptance before posting", async () => {
    await expect(community.create(alice, "No consent")).rejects.toMatchObject({
      code: "COMMUNITY_RULES_REQUIRED",
    });
    await expect(safety.accept(alice, "old-version")).rejects.toMatchObject({
      code: "COMMUNITY_RULES_OUTDATED",
    });
    expect((await safety.rulesStatus(alice)).accepted).toBe(false);
    await safety.accept(alice, COMMUNITY_RULES_VERSION);
    expect((await safety.rulesStatus(alice)).accepted).toBe(true);
  });
  it("blocks in both directions across feeds and interactions; unblock is scoped to its owner", async () => {
    await safety.block(alice, "POST", post);
    expect((await community.list(alice)).items.some((x) => x.id === post)).toBe(
      false,
    );
    await expect(community.react(alice, post, "LIKE")).rejects.toMatchObject({
      code: "POST_NOT_FOUND",
    });
    await expect(
      community.comment(alice, post, "Blocked"),
    ).rejects.toMatchObject({ code: "POST_NOT_FOUND" });
    const ownPost = await community.create(alice, "Alice post");
    expect(
      (await community.list(bob)).items.some((x) => x.id === ownPost.id),
    ).toBe(false);
    await safety.unblock(charlie, bob);
    expect(await safety.blockedIds(alice)).toContain(bob);
    await safety.unblock(alice, bob);
    expect((await community.list(alice)).items.some((x) => x.id === post)).toBe(
      true,
    );
    await expect(safety.block(alice, "USER", alice)).rejects.toMatchObject({
      code: "BLOCK_INVALID",
    });
  });
  it("reports persist idempotently and only authorized moderators can hide content", async () => {
    const report = await safety.report(
      alice,
      "COMMENT",
      comment,
      "Phishing request",
    );
    expect(await safety.report(alice, "COMMENT", comment, "Duplicate")).toEqual(
      report,
    );
    const unauthorized = {
      user: { ...admin.user, permissions: [] },
      requestId: admin.requestId,
    } as unknown as AdminRequest;
    await expect(
      safety.moderate(unauthorized, report.id, "HIDE"),
    ).rejects.toMatchObject({ code: "ADMIN_PERMISSION_REQUIRED" });
    expect(
      (await community.comments(post, undefined, alice)).items.some(
        (x) => x.id === comment,
      ),
    ).toBe(true);
    await safety.moderate(admin, report.id, "HIDE");
    expect(
      (await community.comments(post, undefined, alice)).items.some(
        (x) => x.id === comment,
      ),
    ).toBe(false);
    await expect(
      community.comment(alice, post, "Reply to hidden", comment),
    ).rejects.toMatchObject({ code: "PARENT_NOT_FOUND" });
    expect(
      await prisma.auditLog.count({
        where: { resourceId: report.id, action: "COMMUNITY_REPORT_HIDE" },
      }),
    ).toBe(1);
    await safety.moderate(admin, report.id, "HIDE");
    expect(
      await prisma.auditLog.count({ where: { resourceId: report.id } }),
    ).toBe(1);
  });
  it("hides reported accounts and prevents rules re-acceptance from restoring posting", async () => {
    const report = await safety.reportAuthor(
      alice,
      "POST",
      post,
      "Abusive account",
    );
    await safety.moderate(admin, report.id, "HIDE");
    expect((await community.list(alice)).items.some((x) => x.id === post)).toBe(
      false,
    );
    await expect(
      community.comments(post, undefined, alice),
    ).rejects.toMatchObject({ code: "POST_NOT_FOUND" });
    await expect(community.create(bob, "Bypass")).rejects.toBeDefined();
    await expect(
      safety.accept(bob, COMMUNITY_RULES_VERSION),
    ).rejects.toMatchObject({ code: "COMMUNITY_POSTING_DISABLED" });
  });
});
