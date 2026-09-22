import { Controller, Get, Param, Query } from "@nestjs/common";
import { ApiOperation, ApiQuery, ApiTags } from "@nestjs/swagger";
import { instruments } from "./instruments";
import { MarketDataService } from "./market-data.service";
import {
  MarketCandlesQueryDto,
  MarketInstrumentsQueryDto,
} from "./markets.dto";

@ApiTags("markets")
@Controller("markets")
export class MarketsController {
  constructor(private readonly marketData: MarketDataService) {}

  @Get("instruments")
  @ApiOperation({
    summary:
      "List instruments available from configured display-data providers",
  })
  @ApiQuery({ name: "search", required: false })
  list(@Query() query: MarketInstrumentsQueryDto) {
    const { search } = query;
    const normalized = search?.replaceAll("/", "").trim().toLowerCase();
    const data = normalized
      ? instruments.filter((item) =>
          `${item.symbol.replaceAll("/", "")} ${item.name}`
            .toLowerCase()
            .includes(normalized),
        )
      : instruments;
    return {
      data: data.map((item) => ({
        ...item,
        demoEnabled: true,
        realEnabled: false,
        marketStatus: "DISPLAY_DATA",
      })),
    };
  }

  @Get("instruments/:instrumentId/candles")
  @ApiOperation({ summary: "Get normalized display-only market candles" })
  @ApiQuery({ name: "interval", required: false, example: "1h" })
  @ApiQuery({ name: "limit", required: false, example: 90 })
  @ApiQuery({ name: "before", required: false, type: String })
  candles(
    @Param("instrumentId") instrumentId: string,
    @Query() query: MarketCandlesQueryDto,
  ) {
    return this.marketData.candles(
      instrumentId,
      query.interval,
      query.limit,
      query.before,
    );
  }
}
