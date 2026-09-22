import { Injectable, type NestMiddleware } from "@nestjs/common";
import type { NextFunction, Request, Response } from "express";
import { randomUUID } from "node:crypto";

export type RequestWithId = Request & { requestId: string };

@Injectable()
export class RequestIdMiddleware implements NestMiddleware {
  use(request: RequestWithId, response: Response, next: NextFunction): void {
    const supplied = request.header("x-request-id");
    request.requestId =
      supplied && supplied.length <= 128 ? supplied : randomUUID();
    response.setHeader("X-Request-ID", request.requestId);
    next();
  }
}
