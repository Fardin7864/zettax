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
  PredictionReasonDto,
  PredictionRestrictionDto,
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
  async questions(@Query() query: PredictionQuestionsQueryDto) {
    return { data: await this.predictions.list(query) };
  }

  @Get("questions/:id")
  async question(@Param("id", ParseUUIDPipe) id: string) {
    return { data: await this.predictions.get(id) };
  }

  @Get("mine")
  @UseGuards(AccessTokenGuard)
  async mine(
    @Req() request: AuthenticatedRequest,
    @Query() query: PredictionQuestionsQueryDto = {},
  ) {
    return {
      data: await this.predictions.myPositions(request.auth.userId, query),
    };
  }

  @Get("created")
  @UseGuards(AccessTokenGuard)
  async created(
    @Req() request: AuthenticatedRequest,
    @Query() query: PredictionQuestionsQueryDto,
  ) {
    return { data: await this.predictions.list(query, request.auth.userId) };
  }

  @Get("questions/:id/mine")
  @UseGuards(AccessTokenGuard)
  async questionPositions(
    @Req() request: AuthenticatedRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Query() query: PredictionQuestionsQueryDto,
  ) {
    return {
      data: await this.predictions.myPositions(request.auth.userId, query, id),
    };
  }

  @Get("events")
  @UseGuards(AccessTokenGuard)
  async events(
    @Req() request: AuthenticatedRequest,
    @Query("afterSequence") afterSequence?: string,
  ) {
    return {
      data: await this.predictions.personalEvents(
        request.auth.userId,
        afterSequence,
      ),
    };
  }

  @Post("questions")
  @UseGuards(AccessTokenGuard)
  @Throttle({ default: { limit: 3, ttl: 60 * 60_000 } })
  async create(
    @Req() request: AuthenticatedRequest,
    @Body() body: CreatePredictionQuestionDto,
    @Headers("idempotency-key") key?: string,
  ) {
    return {
      data: await this.predictions.create(
        request.auth.userId,
        body,
        requireIdempotencyKey(key),
      ),
    };
  }

  @Post("questions/:id/report")
  @UseGuards(AccessTokenGuard)
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  async report(
    @Req() request: AuthenticatedRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: PredictionReasonDto,
  ) {
    return {
      data: await this.predictions.report(request.auth.userId, id, body.reason),
    };
  }

  private adminPermission(request: AdminRequest) {
    if (!request.user.permissions.includes("trading.configure"))
      throw new ApiErrorException(
        "ADMIN_PERMISSION_REQUIRED",
        "Trading configuration permission is required.",
        403,
      );
  }
  @Get("admin/questions")
  @UseGuards(AdminGuard)
  async adminQuestions(
    @Req() request: AdminRequest,
    @Query() query: PredictionQuestionsQueryDto,
  ) {
    this.adminPermission(request);
    return { data: await this.predictions.list(query) };
  }
  @Get("admin/reports")
  @UseGuards(AdminGuard)
  async reports(
    @Req() request: AdminRequest,
    @Query() query: PredictionQuestionsQueryDto,
  ) {
    this.adminPermission(request);
    return { data: await this.predictions.reports(query.cursor) };
  }
  @Get("admin/questions/:id/positions")
  @UseGuards(AdminGuard)
  async participants(
    @Req() request: AdminRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Query() query: PredictionQuestionsQueryDto,
  ) {
    this.adminPermission(request);
    return { data: await this.predictions.participants(id, query.cursor) };
  }
  @Post("admin/questions/:id/cancel")
  @UseGuards(AdminGuard)
  async cancel(
    @Req() request: AdminRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: PredictionReasonDto,
  ) {
    this.adminPermission(request);
    return {
      data: await this.predictions.cancel(
        id,
        body.reason,
        request.user.adminId,
      ),
    };
  }
  @Post("admin/questions/:id/retry")
  @UseGuards(AdminGuard)
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  async retry(
    @Req() request: AdminRequest,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    this.adminPermission(request);
    return {
      data: await this.predictions.retrySettlement(id, request.user.adminId),
    };
  }
  @Post("admin/reports/:id/resolve")
  @UseGuards(AdminGuard)
  async resolve(
    @Req() request: AdminRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: PredictionReasonDto,
  ) {
    this.adminPermission(request);
    return {
      data: await this.predictions.resolveReport(
        id,
        body.reason,
        request.user.adminId,
      ),
    };
  }
  @Post("admin/users/:id/creation")
  @UseGuards(AdminGuard)
  async restrict(
    @Req() request: AdminRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: PredictionRestrictionDto,
  ) {
    this.adminPermission(request);
    return {
      data: await this.predictions.restrictCreator(
        id,
        body.enabled,
        body.reason,
        request.user.adminId,
      ),
    };
  }

  @Post("platform/questions")
  @UseGuards(AdminGuard)
  @Throttle({ default: { limit: 20, ttl: 60_000 } })
  async platformCreate(
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
    return { data: await this.predictions.create(null, body) };
  }

  @Post("questions/:id/positions")
  @UseGuards(AccessTokenGuard)
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  async place(
    @Req() request: AuthenticatedRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Body() body: PlacePredictionDto,
  ) {
    return {
      data: await this.predictions.place(
        request.auth.userId,
        id,
        requireIdempotencyKey(idempotencyKey),
        body,
      ),
    };
  }
}
