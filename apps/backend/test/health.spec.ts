import { ConfigService } from "@nestjs/config";
import { describe, expect, it, vi } from "vitest";
import { HealthService } from "../src/health/health.service";

describe("HealthService", () => {
  it("requires every dependency by default", async () => {
    const service = new HealthService(
      new ConfigService({
        DATABASE_URL: "postgresql://database:5432/primevest",
        REDIS_URL: "redis://cache:6379",
        MINIO_ENDPOINT: "objects",
        MINIO_PORT: "9000",
      }),
    );
    const tcp = vi
      .spyOn(service as never, "tcp")
      .mockResolvedValue("up" as never);

    await expect(service.readiness()).resolves.toEqual({
      process: "up",
      postgres: "up",
      redis: "up",
      minio: "up",
    });
    expect(tcp).toHaveBeenCalledTimes(3);
  });

  it("supports Supabase-only local development", async () => {
    const service = new HealthService(
      new ConfigService({
        DATABASE_URL: "postgresql://database:5432/primevest",
        HEALTH_REQUIRE_REDIS: "false",
        HEALTH_REQUIRE_OBJECT_STORAGE: "false",
      }),
    );
    const tcp = vi
      .spyOn(service as never, "tcp")
      .mockResolvedValue("up" as never);

    await expect(service.readiness()).resolves.toEqual({
      process: "up",
      postgres: "up",
    });
    expect(tcp).toHaveBeenCalledOnce();
  });
});
