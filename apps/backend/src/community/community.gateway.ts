import { WebSocketGateway, WebSocketServer } from "@nestjs/websockets";
import type { Server } from "socket.io";

@WebSocketGateway({
  namespace: "/community",
  cors: {
    origin: (process.env.CORS_ORIGINS ?? "http://localhost:3001").split(","),
  },
  transports: ["websocket"],
})
export class CommunityGateway {
  @WebSocketServer()
  private server!: Server;

  changed(post: {
    id: string;
    likeCount: number;
    dislikeCount: number;
    commentCount: number;
    shareCount: number;
    reactionCounts?: Record<string, number>;
  }) {
    this.server?.emit("community:changed", {
      id: post.id,
      likeCount: post.likeCount,
      dislikeCount: post.dislikeCount,
      commentCount: post.commentCount,
      shareCount: post.shareCount,
      ...(post.reactionCounts ? { reactionCounts: post.reactionCounts } : {}),
    });
  }

  created(postId: string) {
    this.server?.emit("community:created", { postId });
  }

  commentCreated(postId: string, comment: Record<string, unknown>) {
    this.server?.emit("community:comment-created", { postId, comment });
  }
}
