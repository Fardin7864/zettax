import {
  Controller,
  Get,
  Headers,
  Param,
  Post,
  Query,
  Req,
  UseGuards,
} from "@nestjs/common";
import { ApiBearerAuth, ApiOperation, ApiTags } from "@nestjs/swagger";
import {
  AccessTokenGuard,
  type AuthenticatedRequest,
} from "../auth/access-token.guard";
import { AccountsService } from "./accounts.service";
import {
  AccountModeParamDto,
  AccountTransactionsQueryDto,
} from "./accounts.dto";
import { requireIdempotencyKey } from "./accounts.validation";

@ApiTags("accounts")
@ApiBearerAuth()
@UseGuards(AccessTokenGuard)
@Controller("accounts")
export class AccountsController {
  constructor(private readonly accounts: AccountsService) {}

  @Get()
  @ApiOperation({ summary: "List authenticated account summaries" })
  async list(@Req() request: AuthenticatedRequest) {
    return { data: await this.accounts.list(request.auth.userId) };
  }

  @Get(":mode/transactions")
  @ApiOperation({ summary: "List ledger activity for one owned account mode" })
  async transactions(
    @Req() request: AuthenticatedRequest,
    @Param() params: AccountModeParamDto,
    @Query() query: AccountTransactionsQueryDto,
  ) {
    return {
      data: await this.accounts.transactions(
        request.auth.userId,
        params.mode,
        query.limit,
        query.cursor,
      ),
    };
  }

  @Post("demo/reset")
  @ApiOperation({ summary: "Reset only the authenticated DEMO account" })
  async resetDemo(
    @Req() request: AuthenticatedRequest,
    @Headers("idempotency-key") key?: string,
  ) {
    return {
      data: await this.accounts.resetDemo(
        request.auth.userId,
        requireIdempotencyKey(key),
      ),
    };
  }
}
