import { ContractDirection, Prisma } from "@prisma/client";

export function proportionalSettlement(
  stake: Prisma.Decimal,
  entry: Prisma.Decimal,
  expiry: Prisma.Decimal,
  direction: ContractDirection,
  feeRate: Prisma.Decimal,
) {
  if (
    !stake.isFinite() ||
    stake.lessThanOrEqualTo(0) ||
    !entry.isFinite() ||
    entry.lessThanOrEqualTo(0) ||
    !expiry.isFinite() ||
    expiry.isNegative() ||
    !feeRate.isFinite() ||
    feeRate.lessThan(0) ||
    feeRate.greaterThan(1)
  ) {
    throw new Error("Invalid proportional settlement inputs");
  }
  const movement = expiry.minus(entry).div(entry);
  const rawPnl = stake
    .mul(movement)
    .mul(direction === ContractDirection.UP ? 1 : -1);
  const grossReturn = Prisma.Decimal.max(0, stake.plus(rawPnl)).toDecimalPlaces(
    2,
    Prisma.Decimal.ROUND_HALF_UP,
  );
  const grossPnl = grossReturn.minus(stake);
  const fee = Prisma.Decimal.max(0, grossPnl)
    .mul(feeRate)
    .toDecimalPlaces(2, Prisma.Decimal.ROUND_HALF_UP);
  return { payout: grossReturn.minus(fee), grossPnl, fee };
}
