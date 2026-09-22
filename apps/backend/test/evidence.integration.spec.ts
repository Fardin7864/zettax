import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import sharp from "sharp";
import { Client } from "minio";
import { afterAll, describe, it, expect } from "vitest";
import { EvidenceService } from "../src/funding/evidence.service";
import { PrismaService } from "../src/database/prisma.service";
const suite =
  process.env.RUN_EVIDENCE_INTEGRATION === "true" ? describe : describe.skip;
suite("real ClamAV and encrypted MinIO evidence integration", () => {
  const prisma = new PrismaService(),
    config = new ConfigService({
      ...process.env,
      EVIDENCE_STORAGE_PROVIDER: "minio",
      MINIO_EVIDENCE_BUCKET: "primevest-evidence-verification",
    });
  const service = new EvidenceService(prisma, config);
  afterAll(() => prisma.$disconnect());
  it("scans, encrypts and verifies a private screenshot round trip", async () => {
    const bytes = await sharp({
      create: { width: 32, height: 32, channels: 3, background: "#daa520" },
    })
      .png()
      .toBuffer();
    const file = {
      buffer: bytes,
      size: bytes.length,
      originalname: "receipt.png",
      mimetype: "image/png",
    } as Express.Multer.File;
    const result = await service.upload(randomUUID(), "USER", "DEPOSIT", file);
    expect(result.status).toBe("CLEAN");
    const read = await service.read(result.id);
    expect((await sharp(read).metadata()).format).toBe("png");
    const storage = new Client({
      endPoint: config.get<string>("MINIO_ENDPOINT")!,
      port: 9000,
      useSSL: false,
      accessKey: config.get<string>("MINIO_ACCESS_KEY")!,
      secretKey: config.get<string>("MINIO_SECRET_KEY")!,
    });
    const stream = await storage.getObject(
        "primevest-evidence-verification",
        result.objectKey,
      ),
      chunks: Buffer[] = [];
    for await (const chunk of stream)
      chunks.push(Buffer.from(chunk as Uint8Array));
    const encrypted = Buffer.concat(chunks);
    expect(encrypted.subarray(0, 4).toString()).toBe("PVE1");
    expect(encrypted.equals(read)).toBe(false);
    const anonymous = new Client({
      endPoint: config.get<string>("MINIO_ENDPOINT")!,
      port: 9000,
      useSSL: false,
    });
    await expect(
      anonymous.getObject("primevest-evidence-verification", result.objectKey),
    ).rejects.toThrow();
  }, 30000);
  it("rejects MIME spoofing, disallowed ownership purposes and scanner test signatures", async () => {
    const bytes = await sharp({
      create: { width: 2, height: 2, channels: 3, background: "#ffffff" },
    })
      .png()
      .toBuffer();
    const file = {
      buffer: bytes,
      size: bytes.length,
      originalname: "receipt.jpg",
      mimetype: "image/jpeg",
    } as Express.Multer.File;
    await expect(
      service.upload(randomUUID(), "USER", "DEPOSIT", file),
    ).rejects.toMatchObject({ code: "EVIDENCE_INVALID" });
    await expect(
      service.upload(randomUUID(), "USER", "RELEASE", file),
    ).rejects.toMatchObject({ code: "EVIDENCE_INVALID" });
    // Standard harmless antivirus test string, not executable malware.
    const eicar = Buffer.from(
      "X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*",
    );
    await expect(service.scan(eicar)).rejects.toThrow();
  });
  it("non-deposit evidence fails closed when the scanner is unreachable", async () => {
    const down = new EvidenceService(
      prisma,
      new ConfigService({
        ...process.env,
        CLAMAV_HOST: "127.0.0.1",
        CLAMAV_PORT: "1",
      }),
    );
    const bytes = await sharp({
      create: { width: 2, height: 2, channels: 3, background: "#ffffff" },
    })
      .png()
      .toBuffer();
    await expect(
      down.upload(randomUUID(), "USER", "KYC", {
        buffer: bytes,
        size: bytes.length,
        originalname: "receipt.png",
        mimetype: "image/png",
      } as Express.Multer.File),
    ).rejects.toMatchObject({ code: "EVIDENCE_SCAN_FAILED" });
  });
});
