import { Module } from "@nestjs/common";
import { ComplianceModule } from "../compliance/compliance.module";
import { AuthModule } from "../auth/auth.module";
import { DemoPriceService } from "./demo-price.service";
import { ExecutionProviderController } from "./execution-provider.controller";
import { ExecutionProviderService } from "./execution-provider.service";
import { MockExecutionProvider } from "./mock-execution.provider";
import { TradingController } from "./trading.controller";
import { TradingService } from "./trading.service";

@Module({
  imports: [AuthModule, ComplianceModule],
  controllers: [ExecutionProviderController, TradingController],
  providers: [
    ExecutionProviderService,
    MockExecutionProvider,
    DemoPriceService,
    TradingService,
  ],
  exports: [ExecutionProviderService, DemoPriceService],
})
export class TradingModule {}
