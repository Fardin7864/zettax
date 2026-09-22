import {
  Body,
  Controller,
  Get,
  Headers,
  HttpStatus,
  Param,
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
import { ApiErrorException } from "../http/api-error";
import {
  CreateOrderDto,
  OrdersQueryDto,
  PositionsQueryDto,
} from "./trading.dto";
import { TradingService } from "./trading.service";

@ApiTags("trading")
@ApiBearerAuth()
@UseGuards(AccessTokenGuard)
@Controller()
export class TradingController {
  constructor(private readonly trading: TradingService) {}

  @Post("orders")
  createOrder(
    @Req() request: AuthenticatedRequest,
    @Headers("idempotency-key") key: string | undefined,
    @Body() body: CreateOrderDto,
  ) {
    return this.trading.createOrder(request.auth.userId, this.key(key), body);
  }

  @Get("orders")
  listOrders(
    @Req() request: AuthenticatedRequest,
    @Query() query: OrdersQueryDto,
  ) {
    return this.trading.listOrders(request.auth.userId, query);
  }

  @Get("positions")
  listPositions(
    @Req() request: AuthenticatedRequest,
    @Query() query: PositionsQueryDto,
  ) {
    return this.trading.listPositions(request.auth.userId, query);
  }

  @Post("positions/:id/close")
  closePosition(
    @Req() request: AuthenticatedRequest,
    @Param("id") id: string,
    @Headers("idempotency-key") key: string | undefined,
  ) {
    return this.trading.closePosition(request.auth.userId, id, this.key(key));
  }

  @Get("trades")
  listTrades(
    @Req() request: AuthenticatedRequest,
    @Query() query: OrdersQueryDto,
  ) {
    return this.trading.listTrades(request.auth.userId, query);
  }

  private key(value: string | undefined): string {
    if (!value || !/^[A-Za-z0-9][A-Za-z0-9:._-]{7,127}$/.test(value)) {
      throw new ApiErrorException(
        "IDEMPOTENCY_KEY_REQUIRED",
        "A valid Idempotency-Key header is required.",
        HttpStatus.BAD_REQUEST,
      );
    }
    return value;
  }
}
