import { Module } from "@nestjs/common";
import { AdminModule } from "../admin/admin.module";
import { AuthModule } from "../auth/auth.module";
import { ComplianceModule } from "../compliance/compliance.module";
import { ControlModule } from "../operations/control.service";
import { TimedContractsModule } from "../timed-contracts/timed-contracts.module";
import { PredictionController } from "./prediction.controller";
import { PredictionGateway } from "./prediction.gateway";
import { PredictionService } from "./prediction.service";

@Module({
  imports: [
    AdminModule,
    AuthModule,
    ComplianceModule,
    ControlModule,
    TimedContractsModule,
  ],
  controllers: [PredictionController],
  providers: [PredictionService, PredictionGateway],
  exports: [PredictionService],
})
export class PredictionModule {}
