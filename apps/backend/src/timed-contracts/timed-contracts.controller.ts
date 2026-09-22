import {
  Body,
  Controller,
  Get,
  Headers,
  Post,
  Query,
  Req,
  UseGuards,
} from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import {
  AccessTokenGuard,
  type AuthenticatedRequest,
} from "../auth/access-token.guard";
import { requireIdempotencyKey } from "../accounts/accounts.validation";
import {
  CreateTimedContractDto,
  TimedContractsQueryDto,
} from "./timed-contracts.dto";
import { TimedContractsService } from "./timed-contracts.service";

@ApiTags("timed-contracts")
@ApiBearerAuth()
@UseGuards(AccessTokenGuard)
@Controller("timed-contracts")
export class TimedContractsController {
  constructor(private readonly contracts: TimedContractsService) {}

  @Post()
  create(
    @Req() request: AuthenticatedRequest,
    @Headers("idempotency-key") key: string | undefined,
    @Body() body: CreateTimedContractDto,
  ) {
    return this.contracts.create(
      request.auth.userId,
      requireIdempotencyKey(key),
      body,
    );
  }

  @Get("terms")
  terms() {
    return this.contracts.terms();
  }

  @Get()
  list(
    @Req() request: AuthenticatedRequest,
    @Query() query: TimedContractsQueryDto,
  ) {
    return this.contracts.list(request.auth.userId, query);
  }
}
