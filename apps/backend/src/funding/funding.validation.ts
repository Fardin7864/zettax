import { HttpStatus } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { fundingError } from "./funding.errors";

const idempotencyPattern = /^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$/;
const mobilePattern = /^\+8801[3-9]\d{8}$/;
const moneyPattern = /^(?:0|[1-9]\d{0,14})(?:\.\d{1,2})?$/;

export function validateIdempotencyKey(value: string | undefined): string {
  const key = value?.trim() ?? "";
  if (!idempotencyPattern.test(key)) {
    fundingError(
      "IDEMPOTENCY_KEY_INVALID",
      "Idempotency-Key must contain 8-128 safe characters",
    );
  }
  return key;
}

export function validateBangladeshMobile(value: string): string {
  const normalized = value.normalize("NFKC").replace(/[\s-]/g, "");
  if (!mobilePattern.test(normalized)) {
    fundingError(
      "MOBILE_INVALID",
      "Mobile number must use the +8801XXXXXXXXX format",
    );
  }
  return normalized;
}

export function normalizeProviderTransactionId(value: string): string {
  const normalized = value
    .normalize("NFKC")
    .trim()
    .toUpperCase()
    .replace(/[\s-]+/g, "");
  if (!/^[A-Z0-9]{6,64}$/.test(normalized)) {
    fundingError(
      "PROVIDER_TRANSACTION_ID_INVALID",
      "Provider transaction ID must contain 6-64 letters or digits",
    );
  }
  return normalized;
}

export function parseBdt(value: string): Prisma.Decimal {
  if (!moneyPattern.test(value)) {
    fundingError(
      "AMOUNT_INVALID",
      "Amount must be a positive BDT value with at most two decimals",
    );
  }
  const amount = new Prisma.Decimal(value);
  if (amount.lessThanOrEqualTo(0)) {
    fundingError("AMOUNT_INVALID", "Amount must be greater than zero");
  }
  return amount;
}

export function parseUsd(value: string): Prisma.Decimal {
  if (!moneyPattern.test(value)) {
    fundingError(
      "AMOUNT_INVALID",
      "Amount must be a positive USD value with at most two decimals",
    );
  }
  const amount = new Prisma.Decimal(value);
  if (amount.lessThanOrEqualTo(0)) {
    fundingError("AMOUNT_INVALID", "Amount must be greater than zero");
  }
  return amount;
}

export type BalancedEntry = {
  direction: "DEBIT" | "CREDIT";
  amount: Prisma.Decimal;
};

export function assertBalanced(entries: BalancedEntry[]): void {
  const debit = entries
    .filter((entry) => entry.direction === "DEBIT")
    .reduce((total, entry) => total.plus(entry.amount), new Prisma.Decimal(0));
  const credit = entries
    .filter((entry) => entry.direction === "CREDIT")
    .reduce((total, entry) => total.plus(entry.amount), new Prisma.Decimal(0));
  if (entries.length < 2 || !debit.equals(credit) || !debit.isPositive()) {
    fundingError(
      "LEDGER_UNBALANCED",
      "Ledger transaction must contain equal positive debits and credits",
      HttpStatus.INTERNAL_SERVER_ERROR,
    );
  }
}
