import { describe, expect, it, vi } from "vitest";
import { CommunityService } from "../src/community/community.service";

describe("community comment replies", () => {
  function setup(parentPostId = "post-1") {
    const post = {
      id: "post-1",
      commentCount: 0,
      likeCount: 0,
      dislikeCount: 0,
      shareCount: 0,
    };
    const parent = {
      id: "parent-1",
      postId: parentPostId,
      replyCount: 0,
      user: { profile: { fullName: "Parent author" } },
    };
    const tx = {
      communityPost: {
        findUnique: vi.fn(async () => ({ id: post.id })),
        update: vi.fn(async () => ({
          ...post,
          commentCount: ++post.commentCount,
        })),
      },
      communityComment: {
        findUnique: vi.fn(async () => parent),
        create: vi.fn(
          async ({
            data,
          }: {
            data: { parentId: string | null; text: string };
          }) => ({
            id: "reply-1",
            parentId: data.parentId,
            text: data.text,
            createdAt: new Date("2026-09-26T10:00:00Z"),
            user: { profile: { fullName: "Reply author" } },
          }),
        ),
        update: vi.fn(async () => ({
          ...parent,
          replyCount: ++parent.replyCount,
        })),
      },
    };
    const prisma = {
      $transaction: (fn: (client: typeof tx) => unknown) => fn(tx),
    };
    const gateway = { changed: vi.fn(), commentCreated: vi.fn() };
    const service = new CommunityService(
      prisma as never,
      {} as never,
      gateway as never,
    );
    return { service, tx, post, parent, gateway };
  }

  it("creates a reply and updates both post and parent counts", async () => {
    const { service, tx, post, parent, gateway } = setup();
    const result = await service.comment(
      "user-1",
      post.id,
      "  Thanks!  ",
      parent.id,
    );
    expect(result).toMatchObject({
      parentId: parent.id,
      text: "Thanks!",
      author: "Reply author",
      replyToAuthor: "Parent author",
      parentReplyCount: 1,
    });
    expect(post.commentCount).toBe(1);
    expect(parent.replyCount).toBe(1);
    expect(tx.communityComment.create).toHaveBeenCalledOnce();
    expect(gateway.commentCreated).toHaveBeenCalledWith(post.id, result);
  });

  it("rejects a reply to a comment on another post", async () => {
    const { service, tx, post } = setup("other-post");
    await expect(
      service.comment("user-1", post.id, "No", "parent-1"),
    ).rejects.toMatchObject({ code: "PARENT_NOT_FOUND" });
    expect(tx.communityComment.create).not.toHaveBeenCalled();
    expect(post.commentCount).toBe(0);
  });
});
