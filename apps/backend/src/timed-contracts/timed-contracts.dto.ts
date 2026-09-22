import { Transform, Type } from "class-transformer";
import { AccountMode, ContractDirection, ContractResult } from "@prisma/client";
import {
  IsEnum,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  Max,
  Min,
} from "class-validator";

export class CreateTimedContractDto {
  @IsString()
  @Matches(/^(?:0(?:\.\d{1,6})?|1(?:\.0{1,6})?)$/)
  expectedProfitFeeRate!: string;
  @Transform(({ value }: { value: unknown }) =>
    typeof value === "string" ? value.toUpperCase() : value,
  )
  @IsEnum(AccountMode)
  accountMode!: AccountMode;

  @IsString()
  @Matches(/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
  instrumentId!: string;

  @IsEnum(ContractDirection)
  direction!: ContractDirection;

  @IsString()
  @Matches(/^(?:0|[1-9]\d*)(?:\.\d{1,2})?$/)
  investmentAmount!: string;

  @IsInt()
  @Min(30)
  @Max(31536000)
  durationSeconds!: number;
}

export class TimedContractsQueryDto {
  @IsOptional()
  @IsUUID()
  cursor?: string;
  @Transform(({ value }: { value: unknown }) =>
    typeof value === "string" ? value.toUpperCase() : value,
  )
  @IsEnum(AccountMode)
  accountMode!: AccountMode;

  @IsOptional()
  @IsEnum(ContractResult)
  result?: ContractResult;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit = 50;
}
