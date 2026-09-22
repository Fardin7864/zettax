import {
  type CallHandler,
  type ExecutionContext,
  Injectable,
  type NestInterceptor,
} from "@nestjs/common";
import type { Observable } from "rxjs";
import { map } from "rxjs/operators";
import type { RequestWithId } from "./request-id.middleware";

type ControllerResult = { data: unknown } | Record<string, unknown>;

@Injectable()
export class ApiEnvelopeInterceptor implements NestInterceptor<
  ControllerResult,
  unknown
> {
  intercept(
    context: ExecutionContext,
    next: CallHandler<ControllerResult>,
  ): Observable<unknown> {
    const request = context.switchToHttp().getRequest<RequestWithId>();
    if (request.path === "/health" || request.path === "/ready") {
      return next.handle();
    }

    return next.handle().pipe(
      map((result) => result === undefined ? result : ({
        ...(Object.hasOwn(result, "data") ? result : { data: result }),
        meta: {
          requestId: request.requestId,
          timestamp: new Date().toISOString(),
        },
      })),
    );
  }
}
