import { describe, expect, it, vi } from "vitest";
import { CommunityGateway } from "../src/community/community.gateway";
describe("community public event privacy", () => {
  it("never broadcasts post or comment content or private database fields", () => {
    const gateway = new CommunityGateway();
    const emit = vi.fn();
    Object.assign(gateway, { server: { emit } });
    const privateRow = {
      id: "post",
      likeCount: 1,
      dislikeCount: 0,
      commentCount: 2,
      shareCount: 0,
      text: "private text",
      authorId: "private user",
      imageEvidenceId: "private evidence",
    };
    gateway.changed(privateRow);
    gateway.commentCreated("post");
    gateway.moderated();
    expect(emit.mock.calls).toEqual([
      [
        "community:changed",
        {
          id: "post",
          likeCount: 1,
          dislikeCount: 0,
          commentCount: 2,
          shareCount: 0,
        },
      ],
      ["community:comment-created", { postId: "post" }],
      ["community:moderated", {}],
    ]);
  });
});
