import { Type } from "class-transformer";
import {
  IsEnum,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
} from "class-validator";
import {
  AccountMode,
  OrderSide,
  OrderStatus,
  PositionStatus,
} from "@prisma/client";

const decimalPattern = /^(?:0|[1-9]\d*)(?:\.\d{1,12})?$/;

export class CreateOrderDto {
  @IsEnum(AccountMode)
  accountMode!: AccountMode;

  @IsString()
  @MaxLength(80)
  @Matches(/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
  instrumentId!: string;

  @IsString()
  @MaxLength(100)
  @Matches(/^[A-Za-z0-9][A-Za-z0-9:._-]{7,99}$/)
  clientOrderId!: string;

  @IsEnum(OrderSide)
  side!: OrderSide;

  @IsIn(["MARKET"])
  orderType = "MARKET" as const;

  @IsString()
  @Matches(decimalPattern)
  quantity!: string;
}

export class AccountModeQueryDto {
  @IsEnum(AccountMode)
  accountMode!: AccountMode;
}

export class OrdersQueryDto extends AccountModeQueryDto {
  @IsOptional()
  @IsEnum(OrderStatus)
  status?: OrderStatus;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit = 50;
}

export class PositionsQueryDto extends AccountModeQueryDto {
  @IsOptional()
  @IsEnum(PositionStatus)
  status?: PositionStatus;
}
