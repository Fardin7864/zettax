import { ConfigService } from "@nestjs/config";
import { createHash, createHmac } from "node:crypto";
import { Readable } from "node:stream";
import { PrismaService } from "../database/prisma.service";
import { ApiErrorException } from "../http/api-error";

const hash = (value: string | Buffer) =>
  createHash("sha256").update(value).digest("hex");
const hmac = (key: string | Buffer, value: string) =>
  createHmac("sha256", key).update(value).digest();
const encode = (value: string) =>
  encodeURIComponent(value).replace(
    /[!'()*]/g,
    (char) => `%${char.charCodeAt(0).toString(16).toUpperCase()}`,
  );

/** Supabase's path-prefixed S3 endpoint uses AWS Signature V4. */
export class SupabaseS3Storage {
  private readonly endpoint: URL;
  private readonly accessKey: string;
  private readonly secretKey: string;
  private readonly region: string;

  constructor(
    config: ConfigService,
    private readonly prisma: PrismaService,
  ) {
    const endpoint = config.get<string>("SUPABASE_S3_ENDPOINT");
    this.accessKey = config.get<string>("SUPABASE_S3_ACCESS_KEY_ID", "");
    this.secretKey = config.get<string>("SUPABASE_S3_SECRET_ACCESS_KEY", "");
    this.region = config.get<string>("SUPABASE_S3_REGION", "us-east-1");
    if (!endpoint || !this.accessKey || !this.secretKey) this.unavailable();
    this.endpoint = new URL(endpoint!);
    if (
      this.endpoint.protocol !== "https:" ||
      this.endpoint.username ||
      this.endpoint.password
    )
      this.unavailable();
  }

  private unavailable(): never {
    throw new ApiErrorException(
      "EVIDENCE_UNAVAILABLE",
      "Private Supabase S3 storage is unavailable.",
      503,
    );
  }

  async request(
    method: string,
    bucket: string,
    objectKey?: string,
    payload?: Buffer,
  ) {
    const path = `${this.endpoint.pathname.replace(/\/$/, "")}/${encode(bucket)}${objectKey === undefined ? "" : `/${objectKey.split("/").map(encode).join("/")}`}`;
    const date = new Date().toISOString().replace(/[:-]|\.\d{3}/g, "");
    const day = date.slice(0, 8);
    const digest = hash(payload ?? "");
    const signedHeaders = "host;x-amz-content-sha256;x-amz-date";
    const canonicalHeaders = `host:${this.endpoint.host}\nx-amz-content-sha256:${digest}\nx-amz-date:${date}\n`;
    const canonical = `${method}\n${path}\n\n${canonicalHeaders}\n${signedHeaders}\n${digest}`;
    const scope = `${day}/${this.region}/s3/aws4_request`;
    const signingKey = hmac(
      hmac(hmac(hmac(`AWS4${this.secretKey}`, day), this.region), "s3"),
      "aws4_request",
    );
    const signature = hmac(
      signingKey,
      `AWS4-HMAC-SHA256\n${date}\n${scope}\n${hash(canonical)}`,
    ).toString("hex");
    try {
      return await fetch(`${this.endpoint.origin}${path}`, {
        method,
        headers: {
          "x-amz-date": date,
          "x-amz-content-sha256": digest,
          Authorization: `AWS4-HMAC-SHA256 Credential=${this.accessKey}/${scope}, SignedHeaders=${signedHeaders}, Signature=${signature}`,
          ...(payload ? { "Content-Type": "application/octet-stream" } : {}),
        },
        ...(payload ? { body: new Uint8Array(payload) } : {}),
        signal: AbortSignal.timeout(20_000),
        redirect: "error",
      });
    } catch {
      this.unavailable();
    }
  }

  async bucketExists(bucket: string) {
    const response = await this.request("HEAD", bucket);
    if (response.status === 404) return false;
    if (!response.ok) this.unavailable();
    return true;
  }

  async makeBucket(bucket: string) {
    if (!(await this.request("PUT", bucket)).ok) this.unavailable();
  }

  async getBucketPolicy(bucket: string) {
    // Supabase S3 does not implement bucket ACL/policy APIs. Check the actual
    // Supabase bucket metadata with the already configured server DB identity.
    const rows = await this.prisma.$queryRaw<{ public: boolean }[]>`
      SELECT public FROM storage.buckets WHERE id = ${bucket}
    `;
    if (!rows[0]) this.unavailable();
    return rows[0].public ? "PUBLIC" : "";
  }

  async putObject(
    bucket: string,
    objectKey: string,
    payload: Buffer,
    _size: number,
    _metadata: Record<string, string>,
  ) {
    if (!(await this.request("PUT", bucket, objectKey, payload)).ok)
      this.unavailable();
  }

  async getObject(bucket: string, objectKey: string) {
    const response = await this.request("GET", bucket, objectKey);
    if (!response.ok || !response.body) this.unavailable();
    return Readable.from(response.body);
  }

  async removeObject(bucket: string, objectKey: string) {
    if (!(await this.request("DELETE", bucket, objectKey)).ok)
      this.unavailable();
  }
}
