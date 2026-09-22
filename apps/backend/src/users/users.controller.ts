import {
  Body,
  Controller,
  Get,
  Post,
  Req,
  UseGuards,
  UploadedFile,
  UseInterceptors,
  Header,
} from "@nestjs/common";
import { FileInterceptor } from "@nestjs/platform-express";
import { Throttle } from "@nestjs/throttler";
import { EVIDENCE_LIMIT } from "../funding/evidence.service";
import { UpdateProfileDto } from "./update-profile.dto";
import { ApiBearerAuth, ApiOperation, ApiTags } from "@nestjs/swagger";
import {
  AccessTokenGuard,
  type AuthenticatedRequest,
} from "../auth/access-token.guard";
import { UsersService } from "./users.service";

@ApiTags("users")
@ApiBearerAuth()
@Controller("users")
export class UsersController {
  constructor(private readonly users: UsersService) {}

  @Post("me/profile")
  @UseGuards(AccessTokenGuard)
  async updateProfile(
    @Req() request: AuthenticatedRequest,
    @Body() body: UpdateProfileDto,
  ) {
    return { data: await this.users.updateProfile(request.auth.userId, body) };
  }

  @Post("me/avatar")
  @UseGuards(AccessTokenGuard)
  @Throttle({ default: { limit: 10, ttl: 60000 } })
  @UseInterceptors(
    FileInterceptor("file", {
      limits: { fileSize: EVIDENCE_LIMIT, files: 1, fields: 0 },
    }),
  )
  async uploadAvatar(
    @Req() request: AuthenticatedRequest,
    @UploadedFile() file: Express.Multer.File,
  ) {
    return { data: await this.users.uploadAvatar(request.auth.userId, file) };
  }

  @Get("me/avatar")
  @UseGuards(AccessTokenGuard)
  @Header("Cache-Control", "private, no-store")
  async avatar(@Req() request: AuthenticatedRequest) {
    return { data: await this.users.avatar(request.auth.userId) };
  }

  @Get("me")
  @UseGuards(AccessTokenGuard)
  @ApiOperation({ summary: "Get the authenticated user and profile" })
  async me(@Req() request: AuthenticatedRequest) {
    return { data: await this.users.me(request.auth.userId) };
  }
}
