import { Module } from "@nestjs/common";
import { AdminModule } from "../admin/admin.module";
import { ComplianceModule } from "../compliance/compliance.module";
import { AuthModule } from "../auth/auth.module";
import { FundingController } from "./funding.controller";
import { FundingService } from "./funding.service";
import { EvidenceService } from "./evidence.service";
import { ControlModule } from "../operations/control.service";

@Module({
  imports: [AuthModule, ComplianceModule, AdminModule, ControlModule],
  controllers: [FundingController],
  providers: [FundingService, EvidenceService],
  exports: [FundingService, EvidenceService],
})
export class FundingModule {}
