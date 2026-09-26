import {
  Body,
  Controller,
  Get,
  Headers,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  Req,
  UseGuards,
} from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { Throttle } from "@nestjs/throttler";
import { AdminGuard, type AdminRequest } from "../admin/admin.module";
import { requireIdempotencyKey } from "../accounts/accounts.validation";
import {
  AccessTokenGuard,
  type AuthenticatedRequest,
} from "../auth/access-token.guard";
import { ApiErrorException } from "../http/api-error";
import {
  CreatePredictionQuestionDto,
  PlacePredictionDto,
  PredictionQuestionsQueryDto,
} from "./prediction.dto";
import { PredictionService } from "./prediction.service";

@ApiTags("prediction")
@ApiBearerAuth()
@Controller("prediction")
export class PredictionController {
  constructor(private readonly predictions: PredictionService) {}

  @Get("availability")
  availability() {
    return { data: this.predictions.availability() };
  }

  @Get("questions")
  questions(@Query() query: PredictionQuestionsQueryDto) {
    return { data: this.predictions.list(query) };
  }

  @Get("questions/:id")
  question(@Param("id", ParseUUIDPipe) id: string) {
    return { data: this.predictions.get(id) };
  }

  @Get("mine")
  @UseGuards(AccessTokenGuard)
  mine(@Req() request: AuthenticatedRequest) {
    return { data: this.predictions.myPositions(request.auth.userId) };
  }

  @Post("questions")
  @UseGuards(AccessTokenGuard)
  @Throttle({ default: { limit: 3, ttl: 60 * 60_000 } })
  create(
    @Req() request: AuthenticatedRequest,
    @Body() body: CreatePredictionQuestionDto,
  ) {
    return { data: this.predictions.create(request.auth.userId, body) };
  }

  @Post("platform/questions")
  @UseGuards(AdminGuard)
  @Throttle({ default: { limit: 20, ttl: 60_000 } })
  platformCreate(
    @Req() request: AdminRequest,
    @Body() body: CreatePredictionQuestionDto,
  ) {
    if (
      !request.user.permissions.includes("trading.configure") ||
      (request.user.stepUpUntil ?? 0) < Date.now()
    ) {
      throw new ApiErrorException(
        "ADMIN_PERMISSION_REQUIRED",
        "Trading configuration and recent step-up verification are required.",
        403,
      );
    }
    return { data: this.predictions.create(null, body) };
  }

  @Post("questions/:id/positions")
  @UseGuards(AccessTokenGuard)
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  place(
    @Req() request: AuthenticatedRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Body() body: PlacePredictionDto,
  ) {
    return {
      data: this.predictions.place(
        request.auth.userId,
        id,
        requireIdempotencyKey(idempotencyKey),
        body,
      ),
    };
  }
}
