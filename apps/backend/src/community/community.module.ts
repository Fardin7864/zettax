import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module";
import { FundingModule } from "../funding/funding.module";
import { CommunityController } from "./community.controller";
import { CommunityGateway } from "./community.gateway";
import { CommunityService } from "./community.service";

@Module({
  imports: [AuthModule, FundingModule],
  controllers: [CommunityController],
  providers: [CommunityGateway, CommunityService],
})
export class CommunityModule {}
