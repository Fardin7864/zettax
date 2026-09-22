import { Controller, Get, ServiceUnavailableException } from "@nestjs/common";
import { ApiExcludeEndpoint } from "@nestjs/swagger";
import { HealthService } from "./health.service";

@Controller()
export class HealthController {
  constructor(private readonly healthService: HealthService) {}

  @Get("health")
  @ApiExcludeEndpoint()
  health() {
    return { status: "ok", service: "zettax-backend" };
  }

  @Get("ready")
  @ApiExcludeEndpoint()
  async ready() {
    const checks = await this.healthService.readiness();
    const ready = Object.values(checks).every((status) => status === "up");
    if (!ready) {
      throw new ServiceUnavailableException({ status: "not_ready", checks });
    }
    return { status: "ready", checks };
  }
}
