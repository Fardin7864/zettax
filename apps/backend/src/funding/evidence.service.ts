import {
  Injectable,
  Logger,
  OnModuleInit,
  OnModuleDestroy,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { Client } from "minio";
import sharp from "sharp";
import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
  randomUUID,
} from "node:crypto";
import { readFileSync } from "node:fs";
import { createConnection } from "node:net";
import { PrismaService } from "../database/prisma.service";
import { ApiErrorException } from "../http/api-error";
import { SupabaseEvidenceStorage } from "./supabase-evidence-storage";
import { SupabaseS3Storage } from "./supabase-s3-storage";

export const EVIDENCE_LIMIT = 5 * 1024 * 1024;
@Injectable()
export class EvidenceService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(EvidenceService.name);
  private cleanupTimer?: NodeJS.Timeout;
  private cleaning = false;

  onModuleInit() {
    void this.deleteExpiredDeposits();
    this.cleanupTimer = setInterval(
      () => void this.deleteExpiredDeposits(),
      60_000,
    );
    this.cleanupTimer.unref();
  }

  onModuleDestroy() {
    if (this.cleanupTimer) clearInterval(this.cleanupTimer);
  }

  async deleteExpiredDeposits() {
    if (this.cleaning) return;
    this.cleaning = true;
    try {
      const rows = await this.prisma.evidenceFile.findMany({
        where: {
          purpose: "DEPOSIT",
          status: { not: "DELETED" },
          createdAt: { lte: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000) },
        },
        take: 100,
        orderBy: { createdAt: "asc" },
      });
      for (const row of rows) {
        await this.storage().removeObject(this.bucket(), row.objectKey);
        await this.prisma.evidenceFile.update({
          where: { id: row.id },
          data: { status: "DELETED" },
        });
      }
    } catch (error) {
      this.logger.error("Deposit screenshot cleanup failed; will retry", error);
    } finally {
      this.cleaning = false;
    }
  }
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}
  private storage() {
    if (
      this.config.get<string>("EVIDENCE_STORAGE_PROVIDER") === "supabase-s3"
    ) {
      return new SupabaseS3Storage(this.config, this.prisma);
    }
    if (
      this.config.get<string>("EVIDENCE_STORAGE_PROVIDER", "supabase") ===
      "supabase"
    ) {
      return new SupabaseEvidenceStorage(this.config);
    }
    return new Client({
      endPoint: this.config.get<string>("MINIO_ENDPOINT", "minio"),
      port: Number(this.config.get("MINIO_PORT", 9000)),
      useSSL: this.config.get("MINIO_SSL") === "true",
      accessKey: this.config.get<string>("MINIO_ACCESS_KEY", ""),
      secretKey: this.config.get<string>("MINIO_SECRET_KEY", ""),
    });
  }
  private bucket() {
    return this.config.get<string>(
      this.config
        .get<string>("EVIDENCE_STORAGE_PROVIDER", "supabase")
        .startsWith("supabase")
        ? "SUPABASE_EVIDENCE_BUCKET"
        : "MINIO_EVIDENCE_BUCKET",
      "primevest-evidence",
    );
  }
  private key() {
    const path = this.config.get<string>("EVIDENCE_ENCRYPTION_KEY_FILE");
    if (!path)
      throw new ApiErrorException(
        "EVIDENCE_UNAVAILABLE",
        "Evidence encryption is not configured.",
        503,
      );
    const key = readFileSync(path);
    if (key.length !== 32)
      throw new ApiErrorException(
        "EVIDENCE_UNAVAILABLE",
        "Evidence encryption is not configured.",
        503,
      );
    return key;
  }
  async scan(bytes: Buffer): Promise<void> {
    await new Promise<void>((resolve, reject) => {
      const socket = createConnection({
        host: this.config.get<string>("CLAMAV_HOST", "clamav"),
        port: Number(this.config.get("CLAMAV_PORT", 3310)),
      });
      let result = "";
      socket.setTimeout(15000);
      socket.on("timeout", () => socket.destroy(new Error("Scanner timeout")));
      socket.on("error", reject);
      socket.on("data", (data: Buffer) => {
        result += data.toString();
        if (result.length > 1024)
          socket.destroy(new Error("Scanner response invalid"));
      });
      socket.on("end", () =>
        result.trim().replace(/\0/g, "").endsWith(": OK")
          ? resolve()
          : reject(new Error("Scanner rejected upload")),
      );
      socket.on("connect", () => {
        socket.write("zINSTREAM\0");
        for (let offset = 0; offset < bytes.length; offset += 65536) {
          const chunk = bytes.subarray(offset, offset + 65536);
          const header = Buffer.alloc(4);
          header.writeUInt32BE(chunk.length);
          socket.write(header);
          socket.write(chunk);
        }
        socket.write(Buffer.alloc(4));
      });
    });
  }
  async upload(
    ownerId: string,
    ownerType: "USER" | "ADMIN",
    purpose: string,
    file: Express.Multer.File,
  ) {
    if (
      !file ||
      ![
        "DEPOSIT",
        "WITHDRAWAL",
        "TREASURY",
        "RELEASE",
        "KYC",
        "PROFILE",
      ].includes(purpose) ||
      (ownerType === "USER" && !["DEPOSIT", "KYC", "PROFILE"].includes(purpose))
    )
      throw new ApiErrorException(
        "EVIDENCE_INVALID",
        "Choose an allowed evidence purpose and image.",
        400,
      );
    if (
      file.size > EVIDENCE_LIMIT ||
      !["image/png", "image/jpeg"].includes(file.mimetype) ||
      !/\.(png|jpe?g)$/i.test(file.originalname)
    )
      throw new ApiErrorException(
        "EVIDENCE_INVALID",
        "Upload a PNG or JPEG image up to 5 MB.",
        400,
      );
    const key = this.key();
    const image = sharp(file.buffer, {
      limitInputPixels: 20000000,
      failOn: "warning",
    });
    const metadata = await image.metadata().catch(() => null);
    if (
      !metadata ||
      !["png", "jpeg"].includes(metadata.format ?? "") ||
      (metadata.format === "png") !== (file.mimetype === "image/png")
    )
      throw new ApiErrorException(
        "EVIDENCE_INVALID",
        "Image contents do not match the declared file type.",
        400,
      );
    let bytes: Buffer;
    try {
      if (!["DEPOSIT", "PROFILE"].includes(purpose))
        await this.scan(file.buffer);
      bytes = await (
        purpose === "PROFILE"
          ? image
              .rotate()
              .resize(512, 512, { fit: "cover", withoutEnlargement: true })
          : image.rotate()
      )
        .png()
        .toBuffer();
      if (!["DEPOSIT", "PROFILE"].includes(purpose)) await this.scan(bytes);
    } catch {
      throw new ApiErrorException(
        ["DEPOSIT", "PROFILE"].includes(purpose)
          ? "EVIDENCE_INVALID"
          : "EVIDENCE_SCAN_FAILED",
        ["DEPOSIT", "PROFILE"].includes(purpose)
          ? "The screenshot could not be decoded. Choose a valid PNG or JPEG."
          : "The image could not be cleared by the scanner. No evidence was accepted.",
        ["DEPOSIT", "PROFILE"].includes(purpose) ? 400 : 503,
      );
    }
    if (bytes.length > EVIDENCE_LIMIT)
      throw new ApiErrorException(
        "EVIDENCE_INVALID",
        "The decoded image is too large. Choose a smaller screenshot.",
        400,
      );
    const id = randomUUID(),
      objectKey = `${purpose.toLowerCase()}/${ownerId}/${id}.enc`;
    const iv = randomBytes(12),
      cipher = createCipheriv("aes-256-gcm", key, iv);
    cipher.setAAD(Buffer.from(objectKey));
    const encrypted = Buffer.concat([cipher.update(bytes), cipher.final()]);
    const payload = Buffer.concat([
      Buffer.from("PVE1"),
      iv,
      cipher.getAuthTag(),
      encrypted,
    ]);
    const storage = this.storage(),
      bucket = this.bucket();
    if (!(await storage.bucketExists(bucket))) {
      try {
        await storage.makeBucket(bucket);
      } catch {
        if (!(await storage.bucketExists(bucket)))
          throw new ApiErrorException(
            "EVIDENCE_UNAVAILABLE",
            "Private storage is unavailable.",
            503,
          );
      }
    }
    // A configured public policy must never silently expose this bucket.
    const policy = await storage
      .getBucketPolicy(bucket)
      .catch((error: unknown) => {
        if (
          error &&
          typeof error === "object" &&
          "code" in error &&
          error.code === "NoSuchBucketPolicy"
        )
          return "";
        throw error;
      });
    if (policy && policy !== "{}")
      throw new ApiErrorException(
        "EVIDENCE_STORAGE_POLICY",
        "Private storage policy requires operator review.",
        503,
      );
    await storage.putObject(bucket, objectKey, payload, payload.length, {
      "Content-Type": "application/octet-stream",
    });
    const saved = await this.prisma.evidenceFile.create({
      data: {
        id,
        ownerId,
        ownerType,
        purpose,
        objectKey,
        filename: "evidence.png",
        mimeType: "image/png",
        sha256: createHash("sha256").update(bytes).digest("hex"),
        sizeBytes: bytes.length,
        status: "CLEAN",
      },
    });
    return { id: saved.id, objectKey: saved.objectKey, status: saved.status };
  }
  async read(id: string) {
    const row = await this.prisma.evidenceFile.findUnique({ where: { id } });
    if (
      !row ||
      row.status !== "CLEAN" ||
      (row.purpose === "DEPOSIT" &&
        row.createdAt.getTime() <= Date.now() - 7 * 24 * 60 * 60 * 1000)
    )
      throw new ApiErrorException(
        "EVIDENCE_NOT_FOUND",
        "Evidence is unavailable.",
        404,
      );
    const stream = await this.storage().getObject(this.bucket(), row.objectKey);
    const chunks: Buffer[] = [];
    let size = 0;
    for await (const chunk of stream) {
      const bytes = Buffer.from(chunk as Uint8Array);
      size += bytes.length;
      if (size > EVIDENCE_LIMIT + 32) throw new Error("Evidence oversized");
      chunks.push(bytes);
    }
    const payload = Buffer.concat(chunks);
    if (payload.subarray(0, 4).toString() !== "PVE1")
      throw new Error("Invalid encrypted evidence");
    const decipher = createDecipheriv(
      "aes-256-gcm",
      this.key(),
      payload.subarray(4, 16),
    );
    decipher.setAAD(Buffer.from(row.objectKey));
    decipher.setAuthTag(payload.subarray(16, 32));
    const bytes = Buffer.concat([
      decipher.update(payload.subarray(32)),
      decipher.final(),
    ]);
    if (createHash("sha256").update(bytes).digest("hex") !== row.sha256)
      throw new Error("Evidence integrity failure");
    return bytes;
  }
}
