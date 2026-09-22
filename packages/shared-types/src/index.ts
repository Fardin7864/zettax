export const complianceModes = [
  "DEMO_ONLY",
  "SANDBOX",
  "PRODUCTION_APPROVED",
] as const;
export type ComplianceMode = (typeof complianceModes)[number];

export type ApiEnvelope<T> = {
  data: T;
  meta: { requestId: string; timestamp: string };
};

export type ApiError = {
  code: string;
  message: string;
  requestId: string;
  details?: Record<string, unknown>;
};

export const authErrorCodes = [
  "AUTH_INVALID_CREDENTIALS",
  "AUTH_SESSION_EXPIRED",
  "AUTH_SESSION_NOT_FOUND",
  "AUTH_ACCOUNT_EXISTS",
  "AUTH_MINIMUM_AGE_REQUIRED",
  "ACCOUNT_SUSPENDED",
] as const;
export type AuthErrorCode = (typeof authErrorCodes)[number];

export type AuthTokenResponse = {
  accessToken: string;
  refreshToken: string;
  tokenType: "Bearer";
  accessTokenExpiresIn: number;
  user: { id: string; email: string; phone: string };
};
