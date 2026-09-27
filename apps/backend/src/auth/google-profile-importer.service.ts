import { Injectable, Logger } from "@nestjs/common";
import sharp from "sharp";
import { PrismaService } from "../database/prisma.service";
import { EvidenceService } from "../funding/evidence.service";

const MAX_GOOGLE_IMAGE_BYTES = 2 * 1024 * 1024;

function verifiedGoogleImageUrl(value: string): URL {
  const url = new URL(value);
  if (
    url.protocol !== "https:" ||
    !url.hostname.endsWith(".googleusercontent.com") ||
    url.username ||
    url.password ||
    (url.port && url.port !== "443")
  ) {
    throw new Error("Unsupported Google profile image URL");
  }
  return url;
}

async function downloadGoogleImage(value: string): Promise<Buffer> {
  let url = verifiedGoogleImageUrl(value);
  const signal = AbortSignal.timeout(5000);
  for (let redirect = 0; redirect <= 2; redirect++) {
    const response = await fetch(url, { redirect: "manual", signal });
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      const location = response.headers.get("location");
      if (!location || redirect === 2)
        throw new Error("Google profile image redirected too many times");
      url = verifiedGoogleImageUrl(new URL(location, url).toString());
      continue;
    }
    if (!response.ok || !response.body)
      throw new Error("Google profile image is unavailable");
    const declaredLength = Number(response.headers.get("content-length") ?? 0);
    if (declaredLength > MAX_GOOGLE_IMAGE_BYTES)
      throw new Error("Google profile image is too large");
    const reader = response.body.getReader();
    const chunks: Buffer[] = [];
    let length = 0;
    while (true) {
      const next = (await reader.read()) as {
        done: boolean;
        value?: Uint8Array;
      };
      if (next.done) break;
      const chunk = next.value;
      if (!chunk) throw new Error("Google profile image is invalid");
      length += chunk.byteLength;
      if (length > MAX_GOOGLE_IMAGE_BYTES) {
        await reader.cancel();
        throw new Error("Google profile image is too large");
      }
      chunks.push(Buffer.from(chunk));
    }
    return Buffer.concat(chunks);
  }
  throw new Error("Google profile image is unavailable");
}

@Injectable()
export class GoogleProfileImporter {
  private readonly logger = new Logger(GoogleProfileImporter.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly evidence: EvidenceService,
  ) {}

  async importMissing(
    userId: string,
    claims: { name: string | undefined; picture: string | undefined },
  ) {
    const fullName = claims.name
      ?.replace(/[\p{Cc}\p{Cf}]/gu, "")
      .trim()
      .replace(/\s+/g, " ")
      .slice(0, 100);
    let profile = await this.prisma.userProfile.findUnique({
      where: { userId },
      select: { avatarObjectKey: true },
    });
    if (!profile && fullName) {
      profile = await this.prisma.userProfile.upsert({
        where: { userId },
        create: {
          userId,
          fullName,
          currentAddress: "",
          district: "",
          country: "Not set",
        },
        update: {},
        select: { avatarObjectKey: true },
      });
    }
    if (!profile || profile.avatarObjectKey || !claims.picture) return;

    try {
      const source = await downloadGoogleImage(claims.picture);
      const png = await sharp(source, { limitInputPixels: 20_000_000 })
        .rotate()
        .resize(512, 512, { fit: "cover", withoutEnlargement: true })
        .png()
        .toBuffer();
      const saved = await this.evidence.upload(userId, "USER", "PROFILE", {
        originalname: "google-profile.png",
        mimetype: "image/png",
        size: png.length,
        buffer: png,
      } as Express.Multer.File);
      await this.prisma.userProfile.updateMany({
        where: { userId, avatarObjectKey: null },
        data: { avatarObjectKey: saved.objectKey },
      });
    } catch {
      // Identity verification has succeeded; an optional photo must not block login.
      this.logger.warn("Google profile photo could not be imported");
    }
  }
}
