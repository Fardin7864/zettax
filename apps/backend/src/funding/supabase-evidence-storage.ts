import { ConfigService } from "@nestjs/config";
import { Readable } from "node:stream";
import { ApiErrorException } from "../http/api-error";

/** Server-only REST adapter; never exposes the service key to customers. */
export class SupabaseEvidenceStorage {
  private readonly endpoint: string;
  private readonly serviceKey: string;

  constructor(config: ConfigService) {
    const url = config.get<string>("SUPABASE_URL");
    const key = config.get<string>("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !key) {
      throw new ApiErrorException(
        "EVIDENCE_UNAVAILABLE",
        "Supabase Storage is not configured.",
        503,
      );
    }
    const parsed = new URL(url);
    if (
      parsed.protocol !== "https:" &&
      !(
        ["localhost", "127.0.0.1"].includes(parsed.hostname) &&
        parsed.protocol === "http:"
      )
    ) {
      throw new ApiErrorException(
        "EVIDENCE_UNAVAILABLE",
        "Supabase Storage requires a secure endpoint.",
        503,
      );
    }
    this.endpoint = `${parsed.origin}/storage/v1`;
    this.serviceKey = key;
  }

  private unavailable(): never {
    throw new ApiErrorException(
      "EVIDENCE_UNAVAILABLE",
      "Private screenshot storage is unavailable.",
      503,
    );
  }

  private async request(
    path: string,
    method = "GET",
    body?: string | Uint8Array<ArrayBuffer>,
    headers?: Record<string, string>,
  ) {
    try {
      return await fetch(`${this.endpoint}${path}`, {
        method,
        headers: {
          apikey: this.serviceKey,
          Authorization: `Bearer ${this.serviceKey}`,
          ...headers,
        },
        ...(body === undefined ? {} : { body }),
        signal: AbortSignal.timeout(15_000),
        redirect: "error",
      });
    } catch {
      this.unavailable();
    }
  }

  private objectPath(bucket: string, objectKey: string) {
    return `/object/${encodeURIComponent(bucket)}/${objectKey.split("/").map(encodeURIComponent).join("/")}`;
  }

  async bucketExists(bucket: string) {
    const response = await this.request(
      `/bucket/${encodeURIComponent(bucket)}`,
    );
    if (response.status === 404) return false;
    if (!response.ok) this.unavailable();
    return true;
  }

  async makeBucket(bucket: string) {
    const response = await this.request(
      "/bucket",
      "POST",
      JSON.stringify({
        id: bucket,
        name: bucket,
        public: false,
        file_size_limit: 5 * 1024 * 1024 + 32,
        allowed_mime_types: ["application/octet-stream"],
      }),
      { "Content-Type": "application/json" },
    );
    if (!response.ok) this.unavailable();
  }

  async getBucketPolicy(bucket: string) {
    const response = await this.request(
      `/bucket/${encodeURIComponent(bucket)}`,
    );
    if (!response.ok) this.unavailable();
    const data = (await response.json()) as { public?: unknown };
    if (typeof data.public !== "boolean") this.unavailable();
    return data.public ? "PUBLIC" : "";
  }

  async putObject(
    bucket: string,
    objectKey: string,
    payload: Buffer,
    size: number,
    metadata: Record<string, string>,
  ) {
    void size;
    void metadata;
    const response = await this.request(
      this.objectPath(bucket, objectKey),
      "POST",
      new Uint8Array(payload),
      {
        "Content-Type": "application/octet-stream",
        "x-upsert": "false",
      },
    );
    if (!response.ok) this.unavailable();
  }

  async getObject(bucket: string, objectKey: string) {
    const response = await this.request(this.objectPath(bucket, objectKey));
    if (!response.ok || !response.body) this.unavailable();
    return Readable.from(response.body);
  }

  async removeObject(bucket: string, objectKey: string) {
    const response = await this.request(
      `/object/${encodeURIComponent(bucket)}`,
      "DELETE",
      JSON.stringify({ prefixes: [objectKey] }),
      {
        "Content-Type": "application/json",
      },
    );
    if (!response.ok) this.unavailable();
  }
}
