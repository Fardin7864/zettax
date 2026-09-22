import { ConfigService } from "@nestjs/config";
import { describe, expect, it, vi } from "vitest";
import sharp from "sharp";
import { Readable } from "node:stream";
import { EvidenceService } from "../src/funding/evidence.service";
import { PrismaService } from "../src/database/prisma.service";

describe("optional deposit screenshot processing", () => {
  it.each(["DEPOSIT", "PROFILE"])("validates, encrypts and previews %s without calling the scanner", async (purpose) => {
    let saved: Record<string, unknown>;
    let stored: Buffer;
    const prisma = {
      evidenceFile: {
        create: vi.fn().mockImplementation(({ data }) => {
          saved = { ...data, createdAt: new Date() };
          return saved;
        }),
        findUnique: vi.fn().mockImplementation(() => saved),
      },
    } as unknown as PrismaService;
    const service = new EvidenceService(prisma, new ConfigService());
    vi.spyOn(
      service as unknown as { key: () => Buffer },
      "key",
    ).mockReturnValue(Buffer.alloc(32, 7));
    const scan = vi
      .spyOn(service, "scan")
      .mockRejectedValue(new Error("scanner unavailable"));
    vi.spyOn(
      service as unknown as { storage: () => unknown },
      "storage",
    ).mockReturnValue({
      bucketExists: vi.fn().mockResolvedValue(true),
      getBucketPolicy: vi.fn().mockResolvedValue(""),
      putObject: vi.fn().mockImplementation((_bucket, _key, bytes) => {
        stored = bytes;
      }),
      getObject: vi.fn().mockImplementation(() => Readable.from([stored])),
    });
    const image = await sharp({
      create: { width: 8, height: 8, channels: 3, background: "#ffffff" },
    })
      .png()
      .toBuffer();
    const result = await service.upload("test-owner", "USER", purpose, {
      buffer: image,
      size: image.length,
      originalname: "receipt.png",
      mimetype: "image/png",
    } as Express.Multer.File);
    expect(scan).not.toHaveBeenCalled();
    expect((await sharp(await service.read(result.id)).metadata()).format).toBe(
      "png",
    );
    expect(stored!.subarray(0, 4).toString()).toBe("PVE1");
  });
});
