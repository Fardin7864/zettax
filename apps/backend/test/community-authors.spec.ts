import { describe, expect, it, vi } from "vitest";
import { CommunityService } from "../src/community/community.service";

describe("community author identity", () => {
  it("shows the saved name and versioned avatar on posts", async () => {
    const row = {
      id: "post-1",
      text: "Hello",
      imageEvidenceId: null,
      likeCount: 0,
      dislikeCount: 0,
      commentCount: 0,
      shareCount: 0,
      createdAt: new Date("2026-09-27T00:00:00Z"),
      author: {
        id: "author-1",
        profile: { fullName: "Jane Trader", avatarObjectKey: "avatar-key" },
      },
      reactions: [],
    };
    const prisma = {
      communityPost: { findMany: vi.fn(async () => [row]) },
      communityReaction: { groupBy: vi.fn(async () => []) },
    };
    const service = new CommunityService(
      prisma as never,
      {} as never,
      {} as never,
    );

    const result = await service.list("viewer-1");
    expect(result.items[0]).toMatchObject({
      author: "Jane Trader",
      authorId: "author-1",
      authorAvatarUrl: expect.stringMatching(
        /^\/community\/users\/author-1\/avatar\?v=[0-9a-f]{12}$/,
      ),
    });
  });

  it("serves only a clean profile picture owned by that user", async () => {
    const prisma = {
      communityPost: { findFirst: vi.fn(async () => ({ id: "post-1" })) },
      userProfile: {
        findUnique: vi.fn(async () => ({ avatarObjectKey: "avatar-key" })),
      },
      evidenceFile: {
        findFirst: vi.fn(async () => ({ id: "evidence-1" })),
      },
    };
    const evidence = { read: vi.fn(async () => Buffer.from("image")) };
    const service = new CommunityService(
      prisma as never,
      evidence as never,
      {} as never,
    );

    await expect(service.avatar("author-1")).resolves.toEqual(
      Buffer.from("image"),
    );
    expect(prisma.evidenceFile.findFirst).toHaveBeenCalledWith({
      where: {
        objectKey: "avatar-key",
        ownerId: "author-1",
        ownerType: "USER",
        purpose: "PROFILE",
        status: "CLEAN",
      },
      select: { id: true },
    });
  });
});
