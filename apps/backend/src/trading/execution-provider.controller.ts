import { Controller, Get } from "@nestjs/common";
import { ApiOperation, ApiTags } from "@nestjs/swagger";
import { ExecutionProviderService } from "./execution-provider.service";

@ApiTags("trading")
@Controller("execution-provider")
export class ExecutionProviderController {
  constructor(private readonly providers: ExecutionProviderService) {}

  @Get("status")
  @ApiOperation({ summary: "Get public-safe execution provider readiness" })
  status() {
    return this.providers.publicStatus();
  }
}
