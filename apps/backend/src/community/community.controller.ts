import {
  Body,
  Controller,
  Get,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  Req,
  Res,
  UseGuards,
} from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { Throttle } from "@nestjs/throttler";
import type { Response } from "express";
import {
  AccessTokenGuard,
  type AuthenticatedRequest,
} from "../auth/access-token.guard";
import { ApiErrorException } from "../http/api-error";
import { CommunityService } from "./community.service";
import { CreateCommentDto, CreatePostDto, ReactDto } from "./community.dto";

@ApiTags("community")
@ApiBearerAuth()
@Controller("community")
export class CommunityController {
  constructor(private readonly community: CommunityService) {}

  @Get("posts")
  @UseGuards(AccessTokenGuard)
  async posts(
    @Req() request: AuthenticatedRequest,
    @Query("cursor") cursor?: string,
  ) {
    if (
      cursor &&
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        cursor,
      )
    )
      throw new ApiErrorException(
        "CURSOR_INVALID",
        "Invalid page cursor.",
        HttpStatus.BAD_REQUEST,
      );
    return { data: await this.community.list(request.auth.userId, cursor) };
  }

  @Post("posts")
  @UseGuards(AccessTokenGuard)
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  async create(
    @Req() request: AuthenticatedRequest,
    @Body() body: CreatePostDto,
  ) {
    return {
      data: await this.community.create(
        request.auth.userId,
        body.text,
        body.imageEvidenceId,
      ),
    };
  }

  @Post("posts/:id/reaction")
  @UseGuards(AccessTokenGuard)
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  async react(
    @Req() request: AuthenticatedRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: ReactDto,
  ) {
    return {
      data: await this.community.react(request.auth.userId, id, body.value),
    };
  }

  @Get("posts/:id/comments")
  @UseGuards(AccessTokenGuard)
  async comments(
    @Param("id", ParseUUIDPipe) id: string,
    @Query("cursor") cursor?: string,
  ) {
    if (
      cursor &&
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        cursor,
      )
    ) {
      throw new ApiErrorException(
        "CURSOR_INVALID",
        "Invalid page cursor.",
        HttpStatus.BAD_REQUEST,
      );
    }
    return { data: await this.community.comments(id, cursor) };
  }

  @Post("posts/:id/comments")
  @UseGuards(AccessTokenGuard)
  @Throttle({ default: { limit: 15, ttl: 60_000 } })
  async comment(
    @Req() request: AuthenticatedRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: CreateCommentDto,
  ) {
    return {
      data: await this.community.comment(
        request.auth.userId,
        id,
        body.text,
        body.parentId,
      ),
    };
  }

  @Post("posts/:id/share")
  @UseGuards(AccessTokenGuard)
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  async share(
    @Req() request: AuthenticatedRequest,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return { data: await this.community.share(request.auth.userId, id) };
  }

  @Get("posts/:id/image")
  async image(
    @Param("id", ParseUUIDPipe) id: string,
    @Res() response: Response,
  ) {
    const bytes = await this.community.image(id);
    response.setHeader("Content-Type", "image/jpeg");
    response.setHeader("Cache-Control", "public, max-age=86400, immutable");
    response.send(bytes);
  }
}
