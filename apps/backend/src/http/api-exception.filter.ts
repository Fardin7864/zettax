import {
  ArgumentsHost,
  BadRequestException,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from "@nestjs/common";
import type { Response } from "express";
import type { RequestWithId } from "./request-id.middleware";
import { ApiErrorException } from "./api-error";

@Catch()
export class ApiExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(ApiExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const context = host.switchToHttp();
    const request = context.getRequest<RequestWithId>();
    const response = context.getResponse<Response>();

    if (exception instanceof ApiErrorException) {
      response.status(exception.getStatus()).json({
        code: exception.code,
        message: exception.message,
        requestId: request.requestId,
        ...(exception.details ? { details: exception.details } : {}),
      });
      return;
    }

    if (exception instanceof BadRequestException) {
      const payload = exception.getResponse();
      const messages =
        typeof payload === "object" && payload !== null && "message" in payload
          ? payload.message
          : undefined;
      response.status(HttpStatus.BAD_REQUEST).json({
        code: "VALIDATION_FAILED",
        message: "The request contains invalid fields.",
        requestId: request.requestId,
        ...(Array.isArray(messages) ? { details: { messages } } : {}),
      });
      return;
    }

    const status =
      exception instanceof HttpException
        ? exception.getStatus()
        : HttpStatus.INTERNAL_SERVER_ERROR;
    if (status >= HttpStatus.INTERNAL_SERVER_ERROR) {
      const detail =
        exception instanceof Error
          ? exception.stack ?? exception.message
          : String(exception);
      this.logger.error(
        `${request.method} ${request.path} failed (requestId=${request.requestId})`,
        detail,
      );
    }
    response.status(status).json({
      code: status === 429 ? "RATE_LIMITED" : "INTERNAL_ERROR",
      message:
        status === 429
          ? "Too many requests. Please try again later."
          : "The request could not be completed.",
      requestId: request.requestId,
    });
  }
}
