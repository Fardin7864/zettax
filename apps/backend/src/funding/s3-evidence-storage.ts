import { ConfigService } from "@nestjs/config";
import {
  CreateBucketCommand,
  DeleteObjectCommand,
  GetBucketPolicyCommand,
  GetObjectCommand,
  HeadBucketCommand,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";
import { Readable } from "node:stream";
import { ApiErrorException } from "../http/api-error";

/** S3-compatible storage using the maintained AWS SDK; retains MINIO_* configuration. */
export class S3EvidenceStorage {
  private readonly client: S3Client;
  destroy() {
    this.client.destroy();
  }
  constructor(config: ConfigService, client?: S3Client) {
    const host = config.get<string>("MINIO_ENDPOINT", "minio");
    const port = Number(config.get("MINIO_PORT", 9000));
    const ssl = config.get("MINIO_SSL") === "true";
    const insecureLocal = [
      "localhost",
      "127.0.0.1",
      "minio",
      "10.0.2.2",
    ].includes(host);
    if (
      !/^[a-zA-Z0-9.-]+$/.test(host) ||
      !Number.isInteger(port) ||
      port < 1 ||
      port > 65535 ||
      (!ssl && (config.get("NODE_ENV") === "production" || !insecureLocal))
    )
      throw new ApiErrorException(
        "EVIDENCE_UNAVAILABLE",
        "Private storage requires a secure endpoint.",
        503,
      );
    this.client =
      client ??
      new S3Client({
        endpoint: `${ssl ? "https" : "http"}://${host}:${port}`,
        region: config.get<string>("MINIO_REGION", "us-east-1"),
        forcePathStyle: true,
        credentials: {
          accessKeyId: config.get<string>("MINIO_ACCESS_KEY", ""),
          secretAccessKey: config.get<string>("MINIO_SECRET_KEY", ""),
        },
        followRegionRedirects: false,
        maxAttempts: 2,
        requestHandler: { connectionTimeout: 8000, requestTimeout: 20000 },
      });
  }
  async bucketExists(bucket: string) {
    try {
      await this.client.send(new HeadBucketCommand({ Bucket: bucket }));
      return true;
    } catch (error) {
      if (
        error &&
        typeof error === "object" &&
        "$metadata" in error &&
        (error.$metadata as { httpStatusCode?: number }).httpStatusCode === 404
      )
        return false;
      throw error;
    }
  }
  async makeBucket(bucket: string) {
    await this.client.send(new CreateBucketCommand({ Bucket: bucket }));
  }
  async getBucketPolicy(bucket: string) {
    try {
      return (
        (await this.client.send(new GetBucketPolicyCommand({ Bucket: bucket })))
          .Policy ?? ""
      );
    } catch (error) {
      if (error instanceof Error && error.name === "NoSuchBucketPolicy")
        return "";
      throw error;
    }
  }
  async putObject(
    bucket: string,
    key: string,
    payload: Buffer,
    size: number,
    metadata: Record<string, string>,
  ) {
    if (payload.length !== size)
      throw new Error("Storage payload size mismatch");
    await this.client.send(
      new PutObjectCommand({
        Bucket: bucket,
        Key: key,
        Body: payload,
        ContentLength: size,
        ContentType: metadata["Content-Type"] ?? "application/octet-stream",
      }),
    );
  }
  async getObject(bucket: string, key: string): Promise<Readable> {
    const response = await this.client.send(
      new GetObjectCommand({ Bucket: bucket, Key: key }),
    );
    if (!response.Body) throw new Error("Storage object body unavailable");
    return response.Body as Readable;
  }
  async removeObject(bucket: string, key: string) {
    await this.client.send(
      new DeleteObjectCommand({ Bucket: bucket, Key: key }),
    );
  }
}
