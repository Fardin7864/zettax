import { Body, Controller, Get, Post, Req, UseGuards } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { Throttle } from "@nestjs/throttler";
import { IsString, Matches } from "class-validator";
import {
  AccessTokenGuard,
  type AuthenticatedRequest,
} from "../auth/access-token.guard";
import { VerificationService } from "./verification.service";

class CodeDto {
  @IsString()
  @Matches(/^\d{6}$/)
  code!: string;
}

@ApiTags("verification")
@ApiBearerAuth()
@UseGuards(AccessTokenGuard)
@Controller("verification")
export class VerificationController {
  constructor(private readonly verification: VerificationService) {}

  @Get("status")
  async status(@Req() request: AuthenticatedRequest) {
    return { data: await this.verification.status(request.auth.userId) };
  }

  @Post("authenticator/setup")
  @Throttle({ default: { limit: 3, ttl: 60_000 } })
  async setup(@Req() request: AuthenticatedRequest) {
    return { data: await this.verification.beginAuthenticator(request.auth.userId) };
  }

  @Post("authenticator/confirm")
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  async confirm(@Req() request: AuthenticatedRequest, @Body() body: CodeDto) {
    return { data: await this.verification.confirmAuthenticator(request.auth.userId, body.code) };
  }

  @Post("email-code")
  @Throttle({ default: { limit: 3, ttl: 60_000 } })
  async emailCode(@Req() request: AuthenticatedRequest) {
    return { data: await this.verification.sendEmailCode(request.auth.userId) };
  }
}
