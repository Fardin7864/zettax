import { HttpStatus } from "@nestjs/common";
import { ApiErrorException } from "../http/api-error";

export class FundingError extends ApiErrorException {
  constructor(
    readonly code: string,
    message: string,
    status: HttpStatus,
  ) {
    super(code, message, status);
  }
}

export function fundingError(
  code: string,
  message: string,
  status: HttpStatus = HttpStatus.BAD_REQUEST,
): never {
  throw new FundingError(code, message, status);
}
