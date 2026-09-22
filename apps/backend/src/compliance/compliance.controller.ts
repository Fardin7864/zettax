import { Controller, Get } from "@nestjs/common";
import { ApiOperation, ApiTags } from "@nestjs/swagger";
import { ComplianceService } from "./compliance.service";

@ApiTags("system")
@Controller("system")
export class ComplianceController {
  constructor(private readonly compliance: ComplianceService) {}

  @Get("config")
  @ApiOperation({
    summary: "Get public-safe effective compliance and app configuration",
  })
  config() {
    return { data: this.compliance.publicConfig() };
  }
}
