import { Type } from "class-transformer";
import { IsEnum, IsInt, IsOptional, Max, Min } from "class-validator";
import { DepositStatus, WithdrawalStatus } from "@prisma/client";

export class FundingPaginationDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(1000000)
  page = 1;
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  pageSize = 25;
}
export class AdminDepositQueryDto extends FundingPaginationDto {
  @IsOptional() @IsEnum(DepositStatus) status?: DepositStatus;
}
export class AdminWithdrawalQueryDto extends FundingPaginationDto {
  @IsOptional() @IsEnum(WithdrawalStatus) status?: WithdrawalStatus;
}
