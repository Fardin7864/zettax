import { ConfigService } from "@nestjs/config";
import { afterEach, describe, expect, it, vi } from "vitest";
import { SupabaseEvidenceStorage } from "../src/funding/supabase-evidence-storage";

const config = () =>
  new ConfigService({
    SUPABASE_URL: "https://project.supabase.co",
    SUPABASE_SERVICE_ROLE_KEY: "server-only-test-key",
  });
describe("private Supabase evidence storage", () => {
  afterEach(() => vi.unstubAllGlobals());
  it("requires server credentials and secure transport", () => {
    expect(() => new SupabaseEvidenceStorage(new ConfigService())).toThrow();
    expect(
      () =>
        new SupabaseEvidenceStorage(
          new ConfigService({
            SUPABASE_URL: "http://example.com",
            SUPABASE_SERVICE_ROLE_KEY: "test",
          }),
        ),
    ).toThrow();
  });
  it("creates a private bucket and uploads encrypted bytes without upsert", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValue(new Response("{}", { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);
    const storage = new SupabaseEvidenceStorage(config());
    await storage.makeBucket("primevest-evidence");
    expect(JSON.parse(fetchMock.mock.calls[0]![1].body).public).toBe(false);
    await storage.putObject(
      "primevest-evidence",
      "deposit/user/image.enc",
      Buffer.from("PVE1"),
      4,
      {},
    );
    expect(fetchMock.mock.calls[1]![0]).toBe(
      "https://project.supabase.co/storage/v1/object/primevest-evidence/deposit/user/image.enc",
    );
    expect(fetchMock.mock.calls[1]![1].headers["x-upsert"]).toBe("false");
    expect(fetchMock.mock.calls[1]![1].headers.Authorization).toBe(
      "Bearer server-only-test-key",
    );
  });
  it("recognizes public buckets so the evidence service rejects them", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(new Response(JSON.stringify({ public: true }))),
    );
    expect(
      await new SupabaseEvidenceStorage(config()).getBucketPolicy("bucket"),
    ).toBe("PUBLIC");
  });
  it("deletes the object using Storage API, not SQL metadata deletion", async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response("[]"));
    vi.stubGlobal("fetch", fetchMock);
    await new SupabaseEvidenceStorage(config()).removeObject(
      "bucket",
      "deposit/image.enc",
    );
    expect(fetchMock.mock.calls[0]![1].method).toBe("DELETE");
    expect(JSON.parse(fetchMock.mock.calls[0]![1].body)).toEqual({
      prefixes: ["deposit/image.enc"],
    });
  });
  it("does not expose provider errors to customers", async () => {
    vi.stubGlobal(
      "fetch",
      vi
        .fn()
        .mockResolvedValue(
          new Response("sensitive-provider-error", { status: 403 }),
        ),
    );
    await expect(
      new SupabaseEvidenceStorage(config()).bucketExists("bucket"),
    ).rejects.toMatchObject({ code: "EVIDENCE_UNAVAILABLE" });
  });
});
