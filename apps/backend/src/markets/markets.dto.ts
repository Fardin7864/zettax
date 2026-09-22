import { Type } from "class-transformer";
import {
  IsIn,
  IsInt,
  IsISO8601,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from "class-validator";
import { MARKET_INTERVALS, type MarketInterval } from "./market-data.provider";

export class MarketInstrumentsQueryDto {
  @IsOptional()
  @IsString()
  @MaxLength(80)
  search?: string;
}

export class MarketCandlesQueryDto {
  @IsOptional()
  @IsIn(MARKET_INTERVALS)
  interval: MarketInterval = "1h";

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(10)
  @Max(200)
  limit = 90;

  @IsOptional()
  @IsISO8601({ strict: true })
  before?: string;
}
