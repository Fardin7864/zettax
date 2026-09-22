import { ConfigService } from "@nestjs/config";
import { afterEach, describe, expect, it, vi } from "vitest";
import { PrismaService } from "../src/database/prisma.service";
import { SupabaseS3Storage } from "../src/funding/supabase-s3-storage";

describe("Supabase S3 evidence", () => {
  afterEach(() => vi.unstubAllGlobals());
  const config = () =>
    new ConfigService({
      SUPABASE_S3_ENDPOINT: "https://project.storage.supabase.co/storage/v1/s3",
      SUPABASE_S3_ACCESS_KEY_ID: "test-id",
      SUPABASE_S3_SECRET_ACCESS_KEY: "test-secret",
    });
  it("signs the full endpoint path and streams encrypted objects", async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response("PVE1"));
    vi.stubGlobal("fetch", fetchMock);
    const storage = new SupabaseS3Storage(config(), {} as PrismaService);
    await storage.putObject(
      "private",
      "deposit/image.enc",
      Buffer.from("PVE1"),
      4,
      {},
    );
    expect(fetchMock.mock.calls[0]![0]).toBe(
      "https://project.storage.supabase.co/storage/v1/s3/private/deposit/image.enc",
    );
    expect(fetchMock.mock.calls[0]![1].headers.Authorization).toMatch(
      /^AWS4-HMAC-SHA256 Credential=test-id\/\d{8}\/us-east-1\/s3\/aws4_request/,
    );
    const chunks: Buffer[] = [];
    for await (const chunk of await storage.getObject(
      "private",
      "deposit/image.enc",
    ))
      chunks.push(Buffer.from(chunk));
    expect(Buffer.concat(chunks).toString()).toBe("PVE1");
  });
  it("checks Supabase bucket metadata instead of unsupported S3 ACLs", async () => {
    const prisma = { $queryRaw: vi.fn().mockResolvedValue([{ public: true }]) };
    const storage = new SupabaseS3Storage(
      config(),
      prisma as unknown as PrismaService,
    );
    expect(await storage.getBucketPolicy("private")).toBe("PUBLIC");
    prisma.$queryRaw.mockResolvedValue([{ public: false }]);
    expect(await storage.getBucketPolicy("private")).toBe("");
  });
});
