import { ConfigService } from "@nestjs/config";
import { S3Client } from "@aws-sdk/client-s3";
import { Readable } from "node:stream";
import { describe, expect, it, vi } from "vitest";
import { S3EvidenceStorage } from "../src/funding/s3-evidence-storage";

describe("private S3-compatible evidence storage", () => {
  function setup() {
    const client = { send: vi.fn(), destroy: vi.fn() };
    const storage = new S3EvidenceStorage(
      new ConfigService({
        MINIO_ENDPOINT: "storage.example.invalid",
        MINIO_PORT: 443,
        MINIO_SSL: "true",
        NODE_ENV: "production",
      }),
      client as unknown as S3Client,
    );
    return { storage, client };
  }
  it("requires TLS in production and rejects endpoint URL injection", () => {
    for (const values of [
      { NODE_ENV: "production", MINIO_ENDPOINT: "localhost" },
      { MINIO_ENDPOINT: "remote.invalid" },
      { MINIO_ENDPOINT: "user@host/path", MINIO_SSL: "true" },
      { MINIO_ENDPOINT: "localhost", MINIO_PORT: -1 },
    ])
      expect(() => new S3EvidenceStorage(new ConfigService(values))).toThrow();
  });
  it("treats only missing bucket and policy responses as absent, failing closed on access errors", async () => {
    const { storage, client } = setup();
    client.send.mockRejectedValueOnce({ $metadata: { httpStatusCode: 404 } });
    expect(await storage.bucketExists("private")).toBe(false);
    client.send.mockRejectedValueOnce(new Error("AccessDenied"));
    await expect(storage.bucketExists("private")).rejects.toThrow(
      "AccessDenied",
    );
    client.send.mockRejectedValueOnce(
      Object.assign(new Error(), { name: "NoSuchBucketPolicy" }),
    );
    expect(await storage.getBucketPolicy("private")).toBe("");
    client.send.mockRejectedValueOnce(new Error("AccessDenied"));
    await expect(storage.getBucketPolicy("private")).rejects.toThrow(
      "AccessDenied",
    );
    client.send.mockResolvedValueOnce({ Policy: "PUBLIC" });
    expect(await storage.getBucketPolicy("private")).toBe("PUBLIC");
  });
  it("preserves encrypted bytes, validates sizes and releases connections", async () => {
    const { storage, client } = setup();
    const body = Buffer.from("encrypted-fixture");
    await expect(
      storage.putObject("private", "key", body, 1, {}),
    ).rejects.toThrow();
    expect(client.send).not.toHaveBeenCalled();
    client.send.mockResolvedValueOnce({});
    await storage.putObject("private", "key", body, body.length, {
      "Content-Type": "application/octet-stream",
    });
    expect(client.send.mock.calls[0]![0].input).toMatchObject({
      Bucket: "private",
      Key: "key",
      Body: body,
      ContentLength: body.length,
    });
    client.send.mockResolvedValueOnce({ Body: Readable.from([body]) });
    const chunks = [];
    for await (const chunk of await storage.getObject("private", "key"))
      chunks.push(Buffer.from(chunk));
    expect(Buffer.concat(chunks)).toEqual(body);
    storage.destroy();
    expect(client.destroy).toHaveBeenCalledOnce();
  });
});
