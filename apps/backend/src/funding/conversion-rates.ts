import { Prisma } from "@prisma/client";
import { fundingError } from "./funding.errors";

export const DEPOSIT_RATE_KEY = "funding.depositBdtPerUsd";
export const WITHDRAWAL_RATE_KEY = "funding.withdrawalBdtPerUsd";

export type ConversionRates = {
  depositBdtPerUsd: Prisma.Decimal;
  withdrawalBdtPerUsd: Prisma.Decimal;
};

export function parseConversionRate(value: string): Prisma.Decimal {
  if (!/^(?:[1-9]\d{0,3})(?:\.\d{1,4})?$/.test(value)) {
    fundingError(
      "CONVERSION_RATE_INVALID",
      "Rate must be from 1 to 9999 BDT per USD, with up to four decimals.",
    );
  }
  return new Prisma.Decimal(value);
}

export async function readConversionRates(
  db: Prisma.TransactionClient,
): Promise<ConversionRates> {
  const rows = await db.systemConfig.findMany({
    where: { key: { in: [DEPOSIT_RATE_KEY, WITHDRAWAL_RATE_KEY] } },
  });
  const configured = new Map(rows.map((row) => [row.key, row.value]));
  const rate = (key: string, fallback: string) => {
    const value = configured.get(key);
    if (value === undefined) return new Prisma.Decimal(fallback);
    if (typeof value !== "string") {
      fundingError("CONVERSION_RATE_INVALID", "Saved conversion rate is invalid.");
    }
    return parseConversionRate(value);
  };
  return {
    depositBdtPerUsd: rate(DEPOSIT_RATE_KEY, "125"),
    withdrawalBdtPerUsd: rate(WITHDRAWAL_RATE_KEY, "118"),
  };
}

export function usdFromDeposit(
  bdtAmount: Prisma.Decimal,
  rate: Prisma.Decimal,
): Prisma.Decimal {
  const usd = bdtAmount.div(rate).toDecimalPlaces(2, Prisma.Decimal.ROUND_HALF_UP);
  if (usd.lessThan("0.01")) {
    fundingError("DEPOSIT_TOO_SMALL", "Deposit must convert to at least $0.01.");
  }
  return usd;
}

export function bdtFromWithdrawal(
  usdAmount: Prisma.Decimal,
  rate: Prisma.Decimal,
): Prisma.Decimal {
  return usdAmount.mul(rate).toDecimalPlaces(2, Prisma.Decimal.ROUND_HALF_UP);
}
