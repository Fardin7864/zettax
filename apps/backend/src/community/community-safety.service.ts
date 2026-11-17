import { Injectable } from "@nestjs/common";
import type { Prisma } from "@prisma/client";
import { PrismaService } from "../database/prisma.service";
import { ApiErrorException } from "../http/api-error";
import type { AdminRequest } from "../admin/admin.module";

export const COMMUNITY_RULES_VERSION = "2026-10-28";
export const COMMUNITY_RULES = {
  version: COMMUNITY_RULES_VERSION,
  title: "Zettax community rules",
  text: "Do not post scams, phishing links, requests for passwords, PINs or verification codes, harassment, hate, threats, sexual or illegal content, or anyone's private information. Share only content you have permission to share. Market posts are opinions, not guaranteed returns. Report unsafe content using the post or comment menu, and block users you do not want to interact with. Zettax may remove content that breaks these rules and restrict abusive accounts. Posts and images are visible to other community members.",
};
export type CommunityTarget = "POST" | "COMMENT" | "USER";

@Injectable()
export class CommunitySafetyService {
  constructor(private readonly prisma: PrismaService) {}

  async rulesStatus(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { communityRulesVersion: true, communityPostingDisabled: true },
    });
    return {
      ...COMMUNITY_RULES,
      accepted:
        user?.communityRulesVersion === COMMUNITY_RULES_VERSION &&
        !user.communityPostingDisabled,
    };
  }

  async reportAuthor(
    userId: string,
    type: CommunityTarget,
    id: string,
    reason: string,
  ) {
    return this.report(userId, "USER", await this.author(type, id), reason);
  }

  async accept(userId: string, version: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { communityPostingDisabled: true },
    });
    if (!user || user.communityPostingDisabled)
      throw new ApiErrorException(
        "COMMUNITY_POSTING_DISABLED",
        "Community posting is restricted. Contact support.",
        403,
      );
    if (version !== COMMUNITY_RULES_VERSION)
      throw new ApiErrorException(
        "COMMUNITY_RULES_OUTDATED",
        "Read the current community rules.",
        400,
      );
    await this.prisma.user.update({
      where: { id: userId },
      data: {
        communityRulesVersion: version,
        communityRulesAcceptedAt: new Date(),
      },
    });
    return { accepted: true, version };
  }

  async assertRules(
    userId: string,
    db: Prisma.TransactionClient = this.prisma,
  ) {
    const user = await db.user.findUnique({
      where: { id: userId },
      select: { communityRulesVersion: true, communityPostingDisabled: true },
    });
    if (
      user?.communityPostingDisabled ||
      user?.communityRulesVersion !== COMMUNITY_RULES_VERSION
    )
      throw new ApiErrorException(
        "COMMUNITY_RULES_REQUIRED",
        "Accept the community rules before posting.",
        403,
      );
  }

  async blockedIds(userId: string, db: Prisma.TransactionClient = this.prisma) {
    const rows = await db.communityBlock.findMany({
      where: { OR: [{ blockerId: userId }, { blockedId: userId }] },
      select: { blockerId: true, blockedId: true },
    });
    return rows.map((row) =>
      row.blockerId === userId ? row.blockedId : row.blockerId,
    );
  }

  async assertVisiblePost(
    userId: string,
    postId: string,
    db: Prisma.TransactionClient = this.prisma,
  ) {
    const post = await db.communityPost.findUnique({
      where: { id: postId },
      select: { authorId: true, hiddenAt: true },
    });
    if (
      !post ||
      post.hiddenAt ||
      (await this.blockedIds(userId, db)).includes(post.authorId)
    )
      throw new ApiErrorException(
        "POST_NOT_FOUND",
        "This post is unavailable.",
        404,
      );
  }

  private async author(targetType: CommunityTarget, id: string) {
    const row =
      targetType === "POST"
        ? await this.prisma.communityPost.findUnique({
            where: { id },
            select: { authorId: true },
          })
        : targetType === "COMMENT"
          ? await this.prisma.communityComment.findUnique({
              where: { id },
              select: { userId: true },
            })
          : await this.prisma.user.findUnique({
              where: { id },
              select: { id: true },
            });
    if (!row)
      throw new ApiErrorException(
        "CONTENT_NOT_FOUND",
        "Content not found.",
        404,
      );
    return "authorId" in row
      ? row.authorId
      : "userId" in row
        ? row.userId
        : row.id;
  }

  async report(
    userId: string,
    targetType: CommunityTarget,
    targetId: string,
    reason: string,
  ) {
    await this.author(targetType, targetId);
    const clean = reason.trim();
    if (!clean || clean.length > 1000)
      throw new ApiErrorException(
        "REPORT_INVALID",
        "Describe the issue in up to 1,000 characters.",
        400,
      );
    const row = await this.prisma.communityReport.upsert({
      where: {
        reporterId_targetType_targetId: {
          reporterId: userId,
          targetType,
          targetId,
        },
      },
      create: { reporterId: userId, targetType, targetId, reason: clean },
      update: {},
      select: { id: true, status: true },
    });
    return row;
  }

  async block(userId: string, targetType: CommunityTarget, targetId: string) {
    const blockedId = await this.author(targetType, targetId);
    if (blockedId === userId)
      throw new ApiErrorException(
        "BLOCK_INVALID",
        "You cannot block yourself.",
        400,
      );
    await this.prisma.communityBlock.upsert({
      where: { blockerId_blockedId: { blockerId: userId, blockedId } },
      create: { blockerId: userId, blockedId },
      update: {},
    });
    return { blocked: true };
  }

  async blocks(userId: string) {
    return this.prisma.communityBlock.findMany({
      where: { blockerId: userId },
      select: {
        blockedId: true,
        createdAt: true,
        blocked: { select: { profile: { select: { fullName: true } } } },
      },
      orderBy: { createdAt: "desc" },
    });
  }

  async unblock(userId: string, blockedId: string) {
    await this.prisma.communityBlock.deleteMany({
      where: { blockerId: userId, blockedId },
    });
    return { blocked: false };
  }

  private moderator(req: AdminRequest) {
    if (!req.user.permissions.includes("community.moderate"))
      throw new ApiErrorException(
        "ADMIN_PERMISSION_REQUIRED",
        "Community moderation permission is required.",
        403,
      );
    if (!req.user.stepUpUntil || req.user.stepUpUntil < Date.now())
      throw new ApiErrorException(
        "ADMIN_STEP_UP_REQUIRED",
        "Verify your identity again before moderating community content.",
        403,
      );
  }

  async reports(req: AdminRequest) {
    this.moderator(req);
    const rows = await this.prisma.communityReport.findMany({
      where: { status: "OPEN" },
      take: 100,
      orderBy: { createdAt: "asc" },
    });
    return Promise.all(
      rows.map(async (row) => {
        const target =
          row.targetType === "POST"
            ? await this.prisma.communityPost.findUnique({
                where: { id: row.targetId },
                select: { text: true, imageEvidenceId: true },
              })
            : row.targetType === "COMMENT"
              ? await this.prisma.communityComment.findUnique({
                  where: { id: row.targetId },
                  select: { text: true },
                })
              : null;
        return {
          ...row,
          imagePath:
            target && "imageEvidenceId" in target && target.imageEvidenceId
              ? `/community/posts/${row.targetId}/image`
              : null,
          content:
            target?.text ??
            (row.targetType === "USER"
              ? "Reported account"
              : "Content unavailable"),
        };
      }),
    );
  }

  async moderate(req: AdminRequest, id: string, action: "HIDE" | "DISMISS") {
    this.moderator(req);
    return this.prisma.$transaction(
      async (tx) => {
        const report = await tx.communityReport.findUnique({ where: { id } });
        if (!report)
          throw new ApiErrorException(
            "REPORT_NOT_FOUND",
            "Report not found.",
            404,
          );
        if (report.status !== "OPEN")
          return {
            status: report.status,
            targetId: report.targetId,
            targetType: report.targetType,
          };
        const hiddenAt = new Date();
        if (action === "HIDE") {
          if (report.targetType === "POST")
            await tx.communityPost.updateMany({
              where: { id: report.targetId },
              data: { hiddenAt },
            });
          else if (report.targetType === "COMMENT")
            await tx.communityComment.updateMany({
              where: { id: report.targetId },
              data: { hiddenAt },
            });
          else {
            await tx.communityPost.updateMany({
              where: { authorId: report.targetId },
              data: { hiddenAt },
            });
            await tx.communityComment.updateMany({
              where: { userId: report.targetId },
              data: { hiddenAt },
            });
            await tx.user.update({
              where: { id: report.targetId },
              data: {
                communityRulesVersion: null,
                communityPostingDisabled: true,
              },
            });
          }
        }
        const updated = await tx.communityReport.update({
          where: { id },
          data: {
            status: action === "HIDE" ? "HIDDEN" : "DISMISSED",
            reviewedAt: hiddenAt,
            reviewedBy: req.user.adminId,
          },
        });
        await tx.auditLog.create({
          data: {
            actorType: "ADMIN",
            actorAdminId: req.user.adminId,
            action: `COMMUNITY_REPORT_${action}`,
            resourceType: "CommunityReport",
            resourceId: id,
            newValue: {
              targetType: report.targetType,
              targetId: report.targetId,
            },
            requestId: req.requestId,
          },
        });
        return {
          status: updated.status,
          targetType: report.targetType,
          targetId: report.targetId,
        };
      },
      { isolationLevel: "Serializable" },
    );
  }
}
