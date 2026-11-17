import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  Req,
  UseGuards,
} from "@nestjs/common";
import { IsIn, IsString, IsUUID, MaxLength } from "class-validator";
import { Throttle } from "@nestjs/throttler";
import {
  AccessTokenGuard,
  type AuthenticatedRequest,
} from "../auth/access-token.guard";
import { AdminGuard, type AdminRequest } from "../admin/admin.module";
import {
  CommunitySafetyService,
  COMMUNITY_RULES,
  type CommunityTarget,
} from "./community-safety.service";
import { CommunityGateway } from "./community.gateway";
class RulesDto {
  @IsString() @MaxLength(40) version!: string;
}
class TargetDto {
  @IsIn(["POST", "COMMENT", "USER"]) targetType!: CommunityTarget;
  @IsUUID() targetId!: string;
}
class ReportDto extends TargetDto {
  @IsString() @MaxLength(1000) reason!: string;
}
class ModerationDto {
  @IsIn(["HIDE", "DISMISS"]) action!: "HIDE" | "DISMISS";
}
@Controller("community")
export class CommunitySafetyController {
  constructor(private readonly safety: CommunitySafetyService) {}
  @Get("rules") rules() {
    return { data: COMMUNITY_RULES };
  }
  @Get("rules/status")
  @UseGuards(AccessTokenGuard)
  async status(@Req() req: AuthenticatedRequest) {
    return { data: await this.safety.rulesStatus(req.auth.userId) };
  }
  @Post("reports/author")
  @UseGuards(AccessTokenGuard)
  @Throttle({ default: { limit: 10, ttl: 60000 } })
  async reportAuthor(
    @Req() req: AuthenticatedRequest,
    @Body() body: ReportDto,
  ) {
    return {
      data: await this.safety.reportAuthor(
        req.auth.userId,
        body.targetType,
        body.targetId,
        body.reason,
      ),
    };
  }
  @Post("rules/accept")
  @UseGuards(AccessTokenGuard)
  async accept(@Req() req: AuthenticatedRequest, @Body() body: RulesDto) {
    return { data: await this.safety.accept(req.auth.userId, body.version) };
  }
  @Post("reports")
  @UseGuards(AccessTokenGuard)
  @Throttle({ default: { limit: 10, ttl: 60000 } })
  async report(@Req() req: AuthenticatedRequest, @Body() body: ReportDto) {
    return {
      data: await this.safety.report(
        req.auth.userId,
        body.targetType,
        body.targetId,
        body.reason,
      ),
    };
  }
  @Post("blocks")
  @UseGuards(AccessTokenGuard)
  @Throttle({ default: { limit: 20, ttl: 60000 } })
  async block(@Req() req: AuthenticatedRequest, @Body() body: TargetDto) {
    return {
      data: await this.safety.block(
        req.auth.userId,
        body.targetType,
        body.targetId,
      ),
    };
  }
  @Get("blocks")
  @UseGuards(AccessTokenGuard)
  async blocks(@Req() req: AuthenticatedRequest) {
    return { data: await this.safety.blocks(req.auth.userId) };
  }
  @Delete("blocks/:id")
  @UseGuards(AccessTokenGuard)
  async unblock(
    @Req() req: AuthenticatedRequest,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return { data: await this.safety.unblock(req.auth.userId, id) };
  }
}
@Controller("admin/community")
@UseGuards(AdminGuard)
export class CommunityModerationController {
  constructor(
    private readonly safety: CommunitySafetyService,
    private readonly gateway: CommunityGateway,
  ) {}
  @Get("reports") async reports(@Req() req: AdminRequest) {
    return { data: await this.safety.reports(req) };
  }
  @Post("reports/:id/resolve")
  async moderate(
    @Req() req: AdminRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: ModerationDto,
  ) {
    const data = await this.safety.moderate(req, id, body.action);
    this.gateway.moderated();
    return { data };
  }
}
