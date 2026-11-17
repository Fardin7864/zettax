import { AdminModule } from "../admin/admin.module";
import { CommunitySafetyService } from "./community-safety.service";
import {
  CommunitySafetyController,
  CommunityModerationController,
} from "./community-safety.controller";
import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module";
import { FundingModule } from "../funding/funding.module";
import { CommunityController } from "./community.controller";
import { CommunityGateway } from "./community.gateway";
import { CommunityService } from "./community.service";

@Module({
  imports: [AuthModule, FundingModule, AdminModule],
  controllers: [
    CommunityController,
    CommunitySafetyController,
    CommunityModerationController,
  ],
  providers: [CommunityGateway, CommunityService, CommunitySafetyService],
})
export class CommunityModule {}
