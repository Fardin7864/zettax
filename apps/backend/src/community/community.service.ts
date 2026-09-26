import { HttpStatus, Injectable } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { PrismaService } from "../database/prisma.service";
import { ApiErrorException } from "../http/api-error";
import { EvidenceService } from "../funding/evidence.service";
import { CommunityGateway } from "./community.gateway";

const authorSelect = { profile: { select: { fullName: true } } } as const;

@Injectable()
export class CommunityService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly evidence: EvidenceService,
    private readonly gateway: CommunityGateway,
  ) {}

  private async serializable<T>(
    work: (tx: Prisma.TransactionClient) => Promise<T>,
  ) {
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        return await this.prisma.$transaction(work, {
          isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
        });
      } catch (error) {
        if (
          !(error instanceof Prisma.PrismaClientKnownRequestError) ||
          error.code !== "P2034" ||
          attempt === 2
        )
          throw error;
      }
    }
    throw new Error("Community transaction unavailable");
  }

  private display(post: {
    id: string;
    text: string;
    imageEvidenceId: string | null;
    likeCount: number;
    dislikeCount: number;
    commentCount: number;
    shareCount: number;
    createdAt: Date;
    author: { profile: { fullName: string } | null };
    reactions?: { value: string }[];
  }) {
    return {
      id: post.id,
      text: post.text,
      imageUrl: post.imageEvidenceId
        ? `/community/posts/${post.id}/image`
        : null,
      author: post.author.profile?.fullName || "Zettax member",
      likeCount: post.likeCount,
      dislikeCount: post.dislikeCount,
      commentCount: post.commentCount,
      shareCount: post.shareCount,
      myReaction: post.reactions?.[0]?.value ?? null,
      createdAt: post.createdAt,
    };
  }

  async list(userId: string, cursor?: string) {
    const rows = await this.prisma.communityPost.findMany({
      take: 21,
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      include: {
        author: { select: authorSelect },
        reactions: { where: { userId }, select: { value: true } },
      },
    });
    const hasMore = rows.length > 20;
    const items = rows.slice(0, 20);
    return {
      items: items.map((row) => this.display(row)),
      nextCursor: hasMore ? items.at(-1)?.id : null,
    };
  }

  async create(
    userId: string,
    textInput: string | undefined,
    imageEvidenceId?: string,
  ) {
    const text = (textInput ?? "").trim();
    if ((!text && !imageEvidenceId) || text.length > 2000)
      throw new ApiErrorException(
        "POST_INVALID",
        "Add text or an image to your post.",
        HttpStatus.BAD_REQUEST,
      );
    const row = await this.serializable(async (tx) => {
      if (imageEvidenceId) {
        const image = await tx.evidenceFile.findUnique({
          where: { id: imageEvidenceId },
        });
        if (
          !image ||
          image.ownerId !== userId ||
          image.purpose !== "COMMUNITY" ||
          image.status !== "CLEAN" ||
          image.claimedBy
        ) {
          throw new ApiErrorException(
            "IMAGE_INVALID",
            "Choose a new image for this post.",
            HttpStatus.BAD_REQUEST,
          );
        }
      }
      const post = await tx.communityPost.create({
        data: {
          authorId: userId,
          text,
          imageEvidenceId: imageEvidenceId ?? null,
        },
        include: { author: { select: authorSelect } },
      });
      if (imageEvidenceId) {
        const claimed = await tx.evidenceFile.updateMany({
          where: { id: imageEvidenceId, claimedBy: null },
          data: { claimedBy: post.id },
        });
        if (claimed.count !== 1)
          throw new ApiErrorException(
            "IMAGE_INVALID",
            "This image was already used.",
            HttpStatus.CONFLICT,
          );
      }
      return post;
    });
    this.gateway.created(row.id);
    return this.display(row);
  }

  async react(
    userId: string,
    postId: string,
    value: "LIKE" | "DISLIKE" | "NONE",
  ) {
    const row = await this.serializable(async (tx) => {
      const post = await tx.communityPost.findUnique({ where: { id: postId } });
      if (!post)
        throw new ApiErrorException(
          "POST_NOT_FOUND",
          "Post not found.",
          HttpStatus.NOT_FOUND,
        );
      const old = await tx.communityReaction.findUnique({
        where: { postId_userId: { postId, userId } },
      });
      if (old?.value === value || (!old && value === "NONE")) return post;
      if (value === "NONE")
        await tx.communityReaction.delete({
          where: { postId_userId: { postId, userId } },
        });
      else
        await tx.communityReaction.upsert({
          where: { postId_userId: { postId, userId } },
          create: { postId, userId, value },
          update: { value },
        });
      return tx.communityPost.update({
        where: { id: postId },
        data: {
          likeCount: {
            increment:
              (value === "LIKE" ? 1 : 0) - (old?.value === "LIKE" ? 1 : 0),
          },
          dislikeCount: {
            increment:
              (value === "DISLIKE" ? 1 : 0) -
              (old?.value === "DISLIKE" ? 1 : 0),
          },
        },
      });
    });
    this.gateway.changed(row);
    return {
      id: row.id,
      likeCount: row.likeCount,
      dislikeCount: row.dislikeCount,
      myReaction: value === "NONE" ? null : value,
    };
  }

  async comments(postId: string, cursor?: string) {
    const rows = await this.prisma.communityComment.findMany({
      where: { postId },
      take: 51,
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
      orderBy: [{ createdAt: "asc" }, { id: "asc" }],
      include: {
        user: { select: authorSelect },
        parent: { select: { user: { select: authorSelect } } },
      },
    });
    const items = rows.slice(0, 50).map((row) => ({
      id: row.id,
      parentId: row.parentId,
      text: row.text,
      author: row.user.profile?.fullName || "Zettax member",
      replyToAuthor: row.parent?.user.profile?.fullName || null,
      replyCount: row.replyCount,
      createdAt: row.createdAt,
    }));
    return { items, nextCursor: rows.length > 50 ? items.at(-1)?.id : null };
  }

  async comment(
    userId: string,
    postId: string,
    textInput: string,
    parentId?: string,
  ) {
    const text = textInput.trim();
    if (!text || text.length > 1000)
      throw new ApiErrorException(
        "COMMENT_INVALID",
        "Write a comment up to 1,000 characters.",
        HttpStatus.BAD_REQUEST,
      );
    const result = await this.serializable(async (tx) => {
      const existingPost = await tx.communityPost.findUnique({
        where: { id: postId },
        select: { id: true },
      });
      if (!existingPost)
        throw new ApiErrorException(
          "POST_NOT_FOUND",
          "Post not found.",
          HttpStatus.NOT_FOUND,
        );
      const parent = parentId
        ? await tx.communityComment.findUnique({
            where: { id: parentId },
            include: { user: { select: authorSelect } },
          })
        : null;
      if (parentId && (!parent || parent.postId !== postId)) {
        throw new ApiErrorException(
          "PARENT_NOT_FOUND",
          "The comment you replied to was not found.",
          HttpStatus.BAD_REQUEST,
        );
      }
      const comment = await tx.communityComment.create({
        data: { userId, postId, parentId: parentId ?? null, text },
        include: { user: { select: authorSelect } },
      });
      const updatedParent = parentId
        ? await tx.communityComment.update({
            where: { id: parentId },
            data: { replyCount: { increment: 1 } },
          })
        : null;
      const post = await tx.communityPost.update({
        where: { id: postId },
        data: { commentCount: { increment: 1 } },
      });
      return { comment, post, parent, updatedParent };
    });
    const created = {
      id: result.comment.id,
      parentId: result.comment.parentId,
      text,
      author: result.comment.user.profile?.fullName || "Zettax member",
      replyToAuthor: result.parent?.user.profile?.fullName || null,
      parentReplyCount: result.updatedParent?.replyCount ?? null,
      replyCount: 0,
      createdAt: result.comment.createdAt,
    };
    this.gateway.changed(result.post);
    this.gateway.commentCreated(postId, created);
    return created;
  }

  async share(userId: string, postId: string) {
    const result = await this.serializable(async (tx) => {
      const existing = await tx.communityShare.findUnique({
        where: { postId_userId: { postId, userId } },
      });
      if (existing)
        return tx.communityPost.findUniqueOrThrow({ where: { id: postId } });
      await tx.communityShare.create({ data: { postId, userId } });
      return tx.communityPost.update({
        where: { id: postId },
        data: { shareCount: { increment: 1 } },
      });
    });
    this.gateway.changed(result);
    return { shareCount: result.shareCount };
  }

  async image(postId: string) {
    const row = await this.prisma.communityPost.findUnique({
      where: { id: postId },
      select: { imageEvidenceId: true },
    });
    if (!row?.imageEvidenceId)
      throw new ApiErrorException(
        "IMAGE_NOT_FOUND",
        "Image not found.",
        HttpStatus.NOT_FOUND,
      );
    return this.evidence.read(row.imageEvidenceId);
  }
}
