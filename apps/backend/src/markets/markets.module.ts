import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module";
import { MarketsController } from "./markets.controller";
import { MarketDataService } from "./market-data.service";
import { BinanceMarketDataProvider } from "./providers/binance-market-data.provider";
import { FrankfurterMarketDataProvider } from "./providers/frankfurter-market-data.provider";
import { TwelveDataMarketDataProvider } from "./providers/twelve-data-market-data.provider";
import { MarketRealtimeGateway } from "./market-realtime.gateway";
import { SandboxMarketDataProvider } from "./providers/sandbox-market-data.provider";
import { DemoPriceService } from "../trading/demo-price.service";
import { SampledPriceService } from "./sampled-price.service";

@Module({
  imports: [AuthModule],
  controllers: [MarketsController],
  providers: [
    MarketDataService,
    BinanceMarketDataProvider,
    FrankfurterMarketDataProvider,
    TwelveDataMarketDataProvider,
    SandboxMarketDataProvider,
    DemoPriceService,
    SampledPriceService,
    MarketRealtimeGateway,
  ],
  exports: [MarketDataService],
})
export class MarketsModule {}
