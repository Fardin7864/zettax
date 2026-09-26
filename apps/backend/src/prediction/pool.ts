import { Prisma } from "@prisma/client";

export type PoolEntry = {
  id: string;
  side: "YES" | "NO";
  stake: Prisma.Decimal;
};

function cents(value: Prisma.Decimal): bigint {
  if (!value.isFinite() || value.lessThan(0) || value.decimalPlaces() > 2) {
    throw new Error("Invalid pool amount");
  }
  return BigInt(value.mul(100).toFixed(0));
}

function usd(value: bigint): Prisma.Decimal {
  return new Prisma.Decimal(value.toString()).div(100);
}

/** Zero-fee parimutuel allocation. Every cent is paid out or refunded. */
export function allocatePredictionPool(
  entries: PoolEntry[],
  outcome: "YES" | "NO",
): Map<string, Prisma.Decimal> {
  const winning = entries.filter((entry) => entry.side === outcome);
  const losing = entries.filter((entry) => entry.side !== outcome);
  const winningCents = winning.reduce(
    (sum, entry) => sum + cents(entry.stake),
    0n,
  );
  const losingCents = losing.reduce(
    (sum, entry) => sum + cents(entry.stake),
    0n,
  );
  const result = new Map<string, Prisma.Decimal>();
  if (winningCents === 0n) {
    for (const entry of entries) result.set(entry.id, entry.stake);
    return result;
  }
  for (const entry of losing) result.set(entry.id, new Prisma.Decimal(0));
  const shares = winning.map((entry) => {
    const numerator = losingCents * cents(entry.stake);
    return {
      entry,
      base: numerator / winningCents,
      remainder: numerator % winningCents,
    };
  });
  let remainder =
    losingCents - shares.reduce((sum, item) => sum + item.base, 0n);
  shares.sort((a, b) =>
    a.remainder === b.remainder
      ? a.entry.id.localeCompare(b.entry.id)
      : a.remainder > b.remainder
        ? -1
        : 1,
  );
  for (const item of shares) {
    const extra = remainder > 0n ? 1n : 0n;
    remainder -= extra;
    result.set(item.entry.id, usd(cents(item.entry.stake) + item.base + extra));
  }
  return result;
}

export function predictionOutcome(
  observed: Prisma.Decimal,
  target: Prisma.Decimal,
  condition: "ABOVE" | "BELOW",
): "YES" | "NO" {
  return condition === "ABOVE"
    ? observed.greaterThan(target)
      ? "YES"
      : "NO"
    : observed.lessThan(target)
      ? "YES"
      : "NO";
}
