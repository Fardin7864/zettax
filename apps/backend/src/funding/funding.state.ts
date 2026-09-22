import { HttpStatus } from "@nestjs/common";
import { WithdrawalStatus } from "@prisma/client";
import { fundingError } from "./funding.errors";

export type WithdrawalAction = "START_REVIEW" | "APPROVE" | "START_PROCESSING";

const transitions: Record<
  WithdrawalAction,
  { expected: WithdrawalStatus; next: WithdrawalStatus }
> = {
  START_REVIEW: {
    expected: WithdrawalStatus.REQUESTED,
    next: WithdrawalStatus.UNDER_REVIEW,
  },
  APPROVE: {
    expected: WithdrawalStatus.UNDER_REVIEW,
    next: WithdrawalStatus.APPROVED,
  },
  START_PROCESSING: {
    expected: WithdrawalStatus.APPROVED,
    next: WithdrawalStatus.PROCESSING,
  },
};

export function resolveWithdrawalTransition(
  current: WithdrawalStatus,
  action: WithdrawalAction,
): { next: WithdrawalStatus; replay: boolean } {
  const transition = transitions[action];
  if (current === transition.next)
    return { next: transition.next, replay: true };
  if (current !== transition.expected) {
    fundingError(
      "WITHDRAWAL_INVALID_STATE",
      `Withdrawal must be ${transition.expected} before ${transition.next}`,
      HttpStatus.CONFLICT,
    );
  }
  return { next: transition.next, replay: false };
}

export function canReleaseWithdrawal(
  status: WithdrawalStatus,
  byOwner: boolean,
): boolean {
  if (byOwner) return status === WithdrawalStatus.REQUESTED;
  return (
    [
      WithdrawalStatus.REQUESTED,
      WithdrawalStatus.UNDER_REVIEW,
      WithdrawalStatus.APPROVED,
    ] as WithdrawalStatus[]
  ).includes(status);
}
