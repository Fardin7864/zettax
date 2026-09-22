import { HttpException, HttpStatus } from "@nestjs/common";

export class ApiErrorException extends HttpException {
  constructor(
    readonly code: string,
    message: string,
    status: HttpStatus,
    readonly details?: Record<string, unknown>,
  ) {
    super({ code, message, details }, status);
  }
}
