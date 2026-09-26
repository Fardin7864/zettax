import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module";
import { ComplianceModule } from "../compliance/compliance.module";
import { TradingModule } from "../trading/trading.module";
import { TimedContractsController } from "./timed-contracts.controller";
import { TimedContractsService } from "./timed-contracts.service";
import { ContractPriceService } from "./contract-price.service";
import { ControlModule } from "../operations/control.service";

@Module({
  imports: [AuthModule, ComplianceModule, TradingModule, ControlModule],
  controllers: [TimedContractsController],
  providers: [TimedContractsService, ContractPriceService],
  exports: [TimedContractsService, ContractPriceService],
})
export class TimedContractsModule {}
