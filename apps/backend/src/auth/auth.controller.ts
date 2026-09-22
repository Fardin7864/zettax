import {
  Body,
  Controller,
  Delete,
  Get,
  Headers,
  Ip,
  Param,
  ParseUUIDPipe,
  Post,
  Req,
  UseGuards,
} from "@nestjs/common";
import { ApiBearerAuth, ApiOperation, ApiTags } from "@nestjs/swagger";
import { Throttle } from "@nestjs/throttler";
import {
  AccessTokenGuard,
  type AuthenticatedRequest,
} from "./access-token.guard";
import { AuthService } from "./auth.service";
import { LoginDto } from "./dto/login.dto";
import { GoogleAuthDto } from "./dto/google-auth.dto";
import { RefreshDto } from "./dto/refresh.dto";
import { RegisterDto } from "./dto/register.dto";
import { ChangePasswordDto } from "./dto/change-password.dto";

@ApiTags("auth")
@Controller("auth")
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post("register")
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  @ApiOperation({ summary: "Register with an email address and password" })
  register(
    @Body() body: RegisterDto,
    @Ip() ipAddress: string,
    @Headers("user-agent") userAgent?: string,
  ) {
    return this.authService.register(body, { ipAddress, userAgent });
  }

  @Post("google")
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @ApiOperation({
    summary: "Sign in or register with a verified Google ID token",
  })
  google(
    @Body() body: GoogleAuthDto,
    @Ip() ipAddress: string,
    @Headers("user-agent") userAgent?: string,
  ) {
    return this.authService.google(body, { ipAddress, userAgent });
  }

  @Post("login")
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @ApiOperation({ summary: "Log in and establish a revocable device session" })
  login(
    @Body() body: LoginDto,
    @Ip() ipAddress: string,
    @Headers("user-agent") userAgent?: string,
  ) {
    return this.authService.login(body, { ipAddress, userAgent });
  }

  @Post("refresh")
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  @ApiOperation({ summary: "Rotate a refresh token" })
  refresh(
    @Body() body: RefreshDto,
    @Ip() ipAddress: string,
    @Headers("user-agent") userAgent?: string,
  ) {
    return this.authService.refresh(body.refreshToken, {
      ipAddress,
      userAgent,
    });
  }

  @Post("logout")
  @UseGuards(AccessTokenGuard)
  @ApiBearerAuth()
  logout(@Req() request: AuthenticatedRequest) {
    return this.authService.logout(request.auth);
  }

  @Post("logout-all")
  @UseGuards(AccessTokenGuard)
  @ApiBearerAuth()
  logoutAll(@Req() request: AuthenticatedRequest) {
    return this.authService.logoutAll(request.auth.userId);
  }

  @Post("change-password")
  @UseGuards(AccessTokenGuard)
  @ApiBearerAuth()
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  changePassword(
    @Req() request: AuthenticatedRequest,
    @Body() body: ChangePasswordDto,
  ) {
    return this.authService.changePassword(request.auth, body);
  }

  @Get("sessions")
  @UseGuards(AccessTokenGuard)
  @ApiBearerAuth()
  sessions(@Req() request: AuthenticatedRequest) {
    return this.authService.listSessions(request.auth.userId);
  }

  @Delete("sessions/:sessionId")
  @UseGuards(AccessTokenGuard)
  @ApiBearerAuth()
  revokeSession(
    @Req() request: AuthenticatedRequest,
    @Param("sessionId", new ParseUUIDPipe({ version: "4" })) sessionId: string,
  ) {
    return this.authService.revokeSession(request.auth.userId, sessionId);
  }
}
