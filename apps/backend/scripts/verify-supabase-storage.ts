import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { randomUUID } from "node:crypto";
import { ConfigService } from "@nestjs/config";
import { PrismaService } from "../src/database/prisma.service";
import { SupabaseS3Storage } from "../src/funding/supabase-s3-storage";
import { EvidenceService } from "../src/funding/evidence.service";
import sharp from "sharp";

async function main() {
  const values: Record<string, string> = {};
  for (const line of readFileSync(resolve("../../.env.local"), "utf8").split(
    /\r?\n/,
  )) {
    const match = /^\s*([^#=]+?)\s*=\s*(.*)\s*$/.exec(line);
    if (match) values[match[1]!] = match[2]!.replace(/^"|"$/g, "");
  }
  process.env.DATABASE_URL = values.DATABASE_URL;
  const prisma = new PrismaService();
  const storage = new SupabaseS3Storage(new ConfigService(values), prisma);
  const bucket = values.SUPABASE_EVIDENCE_BUCKET ?? "primevest-evidence";
  const objectKey = `verification/${randomUUID()}.enc`;
  let uploaded = false;
  try {
    const response = await storage.request("HEAD", bucket);
    console.log(`S3 authentication probe: HTTP ${response.status}`);
    if (!response.ok && response.status !== 404) {
      // Report only a provider error code/region, never response headers or keys.
      const detail = await storage.request("GET", bucket);
      const xml = await detail.text();
      console.log(
        `Provider code: ${/<Code>([A-Za-z0-9]+)<\/Code>/.exec(xml)?.[1] ?? "unknown"}`,
      );
      console.log(
        `Expected region: ${/<Region>([a-z0-9-]+)<\/Region>/.exec(xml)?.[1] ?? detail.headers.get("x-amz-bucket-region") ?? "not supplied"}`,
      );
      throw new Error("Storage authentication probe failed");
    }
    if (!(await storage.bucketExists(bucket))) await storage.makeBucket(bucket);
    if (await storage.getBucketPolicy(bucket))
      throw new Error("Bucket is not private");
    console.log("Bucket exists and is private");
    const bytes = Buffer.from(`PVE1 storage verification ${randomUUID()}`);
    await storage.putObject(bucket, objectKey, bytes, bytes.length, {});
    uploaded = true;
    const chunks: Buffer[] = [];
    for await (const chunk of await storage.getObject(bucket, objectKey))
      chunks.push(Buffer.from(chunk));
    if (!Buffer.concat(chunks).equals(bytes))
      throw new Error("Storage round trip mismatch");
    console.log("Upload/download round trip passed");
    await storage.removeObject(bucket, objectKey);
    uploaded = false;
    console.log("Temporary verification object deleted");
    if (process.argv.includes("--screenshot")) {
      const service = new EvidenceService(prisma, new ConfigService(values));
      const image = await sharp({
        create: { width: 8, height: 8, channels: 3, background: "#f8b425" },
      })
        .png()
        .toBuffer();
      const saved = await service.upload(randomUUID(), "USER", "DEPOSIT", {
        buffer: image,
        size: image.length,
        originalname: "verification.png",
        mimetype: "image/png",
      } as Express.Multer.File);
      try {
        const read = await service.read(saved.id);
        if ((await sharp(read).metadata()).format !== "png")
          throw new Error("Screenshot preview mismatch");
        console.log(
          "Deposit screenshot upload/encryption/preview passed without scanner",
        );
      } finally {
        await storage.removeObject(bucket, saved.objectKey);
        await prisma.evidenceFile.delete({ where: { id: saved.id } });
        console.log("Temporary screenshot and its test metadata deleted");
      }
    }
  } finally {
    if (uploaded) await storage.removeObject(bucket, objectKey);
    await prisma.$disconnect();
  }
}

main().catch(() => {
  console.error("Storage verification failed");
  process.exitCode = 1;
});
