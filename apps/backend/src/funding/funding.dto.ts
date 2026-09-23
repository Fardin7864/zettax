import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";
import { PaymentAccountType } from "@prisma/client";
import {
  IsBoolean,
  IsEnum,
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  MaxLength,
} from "class-validator";

export class CreateDepositDto {
  @ApiProperty({ example: "1250.00", description: "BDT amount sent" })
  @IsString()
  amount!: string;

  @ApiPropertyOptional({ description: "BDT per USD rate shown to the customer" })
  @IsOptional()
  @IsString()
  expectedConversionRate?: string;

  @ApiProperty({ format: "uuid" })
  @IsUUID()
  paymentMethodId!: string;

  @ApiProperty({ example: "+8801712345678" })
  @IsString()
  senderMobile!: string;

  @ApiProperty({ example: "AB12CD34" })
  @IsString()
  providerTransactionId!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(512)
  evidenceObjectKey?: string;
}

export class RejectDepositDto {
  @ApiProperty()
  @IsString()
  @MaxLength(500)
  reason!: string;
}

export class CreateWithdrawalDto {
  @ApiProperty({ example: "10.00", description: "USD amount to deduct" })
  @IsString()
  amount!: string;

  @ApiPropertyOptional({ description: "BDT per USD rate shown to the customer" })
  @IsOptional()
  @IsString()
  expectedConversionRate?: string;

  @ApiProperty({ format: "uuid" })
  @IsUUID()
  paymentMethodId!: string;

  @ApiProperty({ example: "+8801712345678" })
  @IsString()
  receiverMobile!: string;
}

export class UpdateConversionRatesDto {
  @ApiProperty({ example: "125.00" })
  @IsString()
  depositBdtPerUsd!: string;

  @ApiProperty({ example: "118.00" })
  @IsString()
  withdrawalBdtPerUsd!: string;
}

export class RejectWithdrawalDto {
  @ApiProperty()
  @IsString()
  @MaxLength(500)
  reason!: string;
}

export class WithdrawalTransitionDto {
  @ApiProperty({ enum: ["START_REVIEW", "APPROVE", "START_PROCESSING"] })
  @IsIn(["START_REVIEW", "APPROVE", "START_PROCESSING"])
  action!: "START_REVIEW" | "APPROVE" | "START_PROCESSING";
}

export class MarkWithdrawalPaidDto {
  @ApiProperty({ example: "AB12CD34" })
  @IsString()
  providerTransactionId!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(512)
  evidenceObjectKey?: string;
}

export class UpdatePaymentMethodDto {
  @ApiProperty({ example: "01885482244" })
  @IsString()
  @Matches(/^01\d{9}$/, {
    message: "accountNumber must be an 11-digit Bangladesh mobile number",
  })
  accountNumber!: string;

  @ApiProperty({ enum: PaymentAccountType })
  @IsEnum(PaymentAccountType)
  accountType!: PaymentAccountType;

  @ApiProperty()
  @IsString()
  @MaxLength(500)
  instructions!: string;

  @ApiProperty({ example: "100.00" })
  @IsString()
  minimumDeposit!: string;

  @ApiProperty({ example: "100000.00" })
  @IsString()
  maximumDeposit!: string;

  @ApiProperty()
  @IsBoolean()
  isEnabled!: boolean;
}
