import { Module } from "@nestjs/common";
import { AdminModule } from "../admin/admin.module";
import { ComplianceModule } from "../compliance/compliance.module";
import { AuthModule } from "../auth/auth.module";
import { FundingController } from "./funding.controller";
import { FundingService } from "./funding.service";
import { EvidenceModule } from "./evidence.module";
import { ControlModule } from "../operations/control.service";
import { VerificationModule } from "../verification/verification.module";

@Module({
  imports: [AuthModule, EvidenceModule, ComplianceModule, AdminModule, ControlModule, VerificationModule],
  controllers: [FundingController],
  providers: [FundingService],
  exports: [FundingService, EvidenceModule],
})
export class FundingModule {}
