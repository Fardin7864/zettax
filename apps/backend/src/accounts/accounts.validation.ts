import { HttpStatus } from "@nestjs/common";
import { ApiErrorException } from "../http/api-error";

const idempotencyPattern = /^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$/;

export function requireIdempotencyKey(value: string | undefined): string {
  const key = value?.trim() ?? "";
  if (!idempotencyPattern.test(key)) {
    throw new ApiErrorException(
      "IDEMPOTENCY_KEY_INVALID",
      "Idempotency-Key must contain 8-128 safe characters.",
      HttpStatus.BAD_REQUEST,
    );
  }
  return key;
}
