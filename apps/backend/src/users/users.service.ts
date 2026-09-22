import { HttpStatus, Injectable } from "@nestjs/common";
import { PrismaService } from "../database/prisma.service";
import { ApiErrorException } from "../http/api-error";
import { EvidenceService } from "../funding/evidence.service";
import { UpdateProfileDto } from "./update-profile.dto";

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService, private readonly evidence: EvidenceService) {}

  async updateProfile(userId: string, body: UpdateProfileDto) {
    const dateOfBirth = new Date(body.dateOfBirth);
    if (!body.fullName.trim() || !body.country.trim() || dateOfBirth > new Date() || dateOfBirth < new Date("1900-01-01")) {
      throw new ApiErrorException("PROFILE_INVALID", "Enter a name, country and valid date of birth.", 400);
    }
    const data = {
      fullName: body.fullName.trim(), dateOfBirth, gender: body.gender ?? null,
      currentAddress: body.currentAddress.trim(), district: body.district.trim(), country: body.country.trim(),
    };
    await this.prisma.userProfile.upsert({ where: { userId }, create: { userId, ...data }, update: data });
    return this.me(userId);
  }

  async uploadAvatar(userId: string, file: Express.Multer.File) {
    const profile = await this.prisma.userProfile.findUnique({ where: { userId } });
    if (!profile) throw new ApiErrorException("PROFILE_REQUIRED", "Save your profile details before uploading a picture.", 400);
    const saved = await this.evidence.upload(userId, "USER", "PROFILE", file);
    await this.prisma.userProfile.update({ where: { userId }, data: { avatarObjectKey: saved.objectKey } });
    return { avatarObjectKey: saved.objectKey };
  }

  async avatar(userId: string) {
    const profile = await this.prisma.userProfile.findUnique({ where: { userId } });
    const file = profile?.avatarObjectKey ? await this.prisma.evidenceFile.findFirst({
      where: { objectKey: profile.avatarObjectKey, ownerId: userId, ownerType: "USER", purpose: "PROFILE", status: "CLEAN" },
    }) : null;
    if (!file) throw new ApiErrorException("AVATAR_NOT_FOUND", "No profile picture is set.", 404);
    return { imageBase64: (await this.evidence.read(file.id)).toString("base64") };
  }

  async me(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        phone: true,
        emailVerifiedAt: true,
        phoneVerifiedAt: true,
        loginEnabled: true,
        tradingEnabled: true,
        depositEnabled: true,
        withdrawalEnabled: true,
        createdAt: true,
        profile: {
          select: {
            fullName: true,
            dateOfBirth: true,
            gender: true,
            currentAddress: true,
            district: true,
            country: true,
            avatarObjectKey: true,
          },
        },
      },
    });
    if (!user) {
      throw new ApiErrorException(
        "USER_NOT_FOUND",
        "The authenticated user was not found.",
        HttpStatus.NOT_FOUND,
      );
    }
    return user;
  }
}
