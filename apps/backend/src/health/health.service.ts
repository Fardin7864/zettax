import { Injectable } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { Socket } from "node:net";

type DependencyStatus = "up" | "down";

@Injectable()
export class HealthService {
  constructor(private readonly config: ConfigService) {}

  async readiness(): Promise<Record<string, DependencyStatus>> {
    const database = new URL(
      this.config.get<string>("DATABASE_URL") ??
        "postgresql://localhost:5432/primevest",
    );
    const checks: Record<string, Promise<DependencyStatus>> = {
      postgres: this.tcp(database.hostname, Number(database.port || 5432)),
    };

    if (this.isRequired("HEALTH_REQUIRE_REDIS")) {
      const redis = new URL(
        this.config.get<string>("REDIS_URL") ?? "redis://localhost:6379",
      );
      checks.redis = this.tcp(redis.hostname, Number(redis.port || 6379));
    }

    if (this.isRequired("HEALTH_REQUIRE_OBJECT_STORAGE")) {
      const minioHost =
        this.config.get<string>("MINIO_ENDPOINT") ?? "localhost";
      const minioPort = Number(this.config.get<string>("MINIO_PORT") ?? "9000");
      checks.minio = this.tcp(minioHost, minioPort);
    }

    const results = await Promise.all(
      Object.entries(checks).map(async ([name, check]) => [name, await check]),
    );
    return { process: "up", ...Object.fromEntries(results) };
  }

  private isRequired(name: string): boolean {
    return this.config.get<string>(name, "true").toLowerCase() !== "false";
  }

  private tcp(host: string, port: number): Promise<DependencyStatus> {
    return new Promise((resolve) => {
      const socket = new Socket();
      const finish = (status: DependencyStatus) => {
        socket.destroy();
        resolve(status);
      };
      socket.setTimeout(1_500);
      socket.once("connect", () => finish("up"));
      socket.once("timeout", () => finish("down"));
      socket.once("error", () => finish("down"));
      socket.connect(port, host);
    });
  }
}
