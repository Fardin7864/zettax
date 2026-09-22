import {
  CanActivate,
  ExecutionContext,
  HttpStatus,
  Injectable,
} from "@nestjs/common";
import type { Request } from "express";
import { AuthService } from "./auth.service";
import type { AuthenticatedPrincipal } from "./auth.types";
import { ApiErrorException } from "../http/api-error";

export type AuthenticatedRequest = Request & {
  auth: AuthenticatedPrincipal;
};

@Injectable()
export class AccessTokenGuard implements CanActivate {
  constructor(private readonly authService: AuthService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const authorization = request.header("authorization");
    if (!authorization?.startsWith("Bearer ")) {
      throw new ApiErrorException(
        "AUTH_SESSION_EXPIRED",
        "Your session has expired. Please sign in again.",
        HttpStatus.UNAUTHORIZED,
      );
    }
    request.auth = await this.authService.validateAccessToken(
      authorization.slice("Bearer ".length),
    );
    return true;
  }
}
