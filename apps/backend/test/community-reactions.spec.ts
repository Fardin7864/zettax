import { describe, expect, it, vi } from "vitest";
import { CommunityService } from "../src/community/community.service";

describe("community reactions", () => {
  it("switches reaction types and broadcasts the updated counts", async () => {
    const post = {
      id: "post-1",
      likeCount: 0,
      dislikeCount: 0,
      commentCount: 0,
      shareCount: 0,
    };
    let selected: string | null = null;
    const tx = {
      communityPost: {
        findUnique: vi.fn(async () => post),
        update: vi.fn(
          async ({
            data,
          }: {
            data: {
              likeCount: { increment: number };
              dislikeCount: { increment: number };
            };
          }) => {
            post.likeCount += data.likeCount.increment;
            post.dislikeCount += data.dislikeCount.increment;
            return post;
          },
        ),
      },
      communityReaction: {
        findUnique: vi.fn(async () => (selected ? { value: selected } : null)),
        upsert: vi.fn(async ({ create }: { create: { value: string } }) => {
          selected = create.value;
        }),
        delete: vi.fn(async () => {
          selected = null;
        }),
      },
    };
    const prisma = {
      $transaction: (fn: (client: typeof tx) => unknown) => fn(tx),
      communityReaction: {
        groupBy: vi.fn(async () =>
          selected ? [{ value: selected, _count: { _all: 1 } }] : [],
        ),
      },
    };
    const gateway = { changed: vi.fn() };
    const service = new CommunityService(
      prisma as never,
      {} as never,
      gateway as never,
    );

    const loved = await service.react("user-1", post.id, "LOVE");
    expect(loved.reactionCounts.LOVE).toBe(1);
    expect(loved.likeCount).toBe(0);
    expect(gateway.changed).toHaveBeenLastCalledWith(
      expect.objectContaining({
        id: post.id,
        reactionCounts: expect.objectContaining({ LOVE: 1 }),
      }),
    );

    const liked = await service.react("user-1", post.id, "LIKE");
    expect(liked.reactionCounts.LOVE).toBe(0);
    expect(liked.reactionCounts.LIKE).toBe(1);
    expect(liked.likeCount).toBe(1);

    const removed = await service.react("user-1", post.id, "NONE");
    expect(removed.reactionCounts.LIKE).toBe(0);
    expect(removed.likeCount).toBe(0);
    expect(removed.myReaction).toBeNull();
  });
});
