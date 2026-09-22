import type { ComplianceMode } from "@primevest/shared-types";

export type Environment = NodeJS.ProcessEnv & {
  COMPLIANCE_MODE: ComplianceMode;
  BACKEND_PORT: string;
  JWT_ACCESS_SECRET: string;
  JWT_REFRESH_SECRET: string;
  JWT_ACCESS_TTL_SECONDS: string;
  JWT_REFRESH_TTL_DAYS: string;
  AUTH_MAX_FAILED_LOGINS: string;
  AUTH_LOCKOUT_MINUTES: string;
  GOOGLE_WEB_CLIENT_ID: string;
};

const modes: ComplianceMode[] = ["DEMO_ONLY", "SANDBOX", "PRODUCTION_APPROVED"];

const unsafeProductionValues = [
  "local-access-secret-change-before-production",
  "local-refresh-secret-change-before-production",
  "local-development-access-secret-32chars",
  "local-development-refresh-secret-32chars",
  "primevest-local-only",
  "change-me-locally",
];

function optionalString(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

export function validateEnvironment(
  input: Record<string, unknown>,
): Environment {
  const environment = { ...input } as Environment;
  const requestedMode = (optionalString(input.COMPLIANCE_MODE) ??
    "DEMO_ONLY") as ComplianceMode;
  environment.COMPLIANCE_MODE = modes.includes(requestedMode)
    ? requestedMode
    : "DEMO_ONLY";
  environment.BACKEND_PORT = optionalString(input.BACKEND_PORT) ?? "3000";
  environment.JWT_ACCESS_SECRET =
    optionalString(input.JWT_ACCESS_SECRET) ??
    "local-access-secret-change-before-production";
  environment.JWT_REFRESH_SECRET =
    optionalString(input.JWT_REFRESH_SECRET) ??
    "local-refresh-secret-change-before-production";
  environment.JWT_ACCESS_TTL_SECONDS = boundedInteger(
    input.JWT_ACCESS_TTL_SECONDS,
    900,
    60,
    3600,
  );
  environment.JWT_REFRESH_TTL_DAYS = boundedInteger(
    input.JWT_REFRESH_TTL_DAYS,
    30,
    1,
    90,
  );
  environment.AUTH_MAX_FAILED_LOGINS = boundedInteger(
    input.AUTH_MAX_FAILED_LOGINS,
    5,
    3,
    20,
  );
  environment.AUTH_LOCKOUT_MINUTES = boundedInteger(
    input.AUTH_LOCKOUT_MINUTES,
    15,
    1,
    1440,
  );
  environment.GOOGLE_WEB_CLIENT_ID =
    optionalString(input.GOOGLE_WEB_CLIENT_ID)?.trim() ?? "";

  if (environment.NODE_ENV === "production") {
    for (const name of [
      "JWT_ACCESS_SECRET",
      "JWT_REFRESH_SECRET",
      "DATABASE_URL",
    ]) {
      const value = optionalString(input[name]) ?? "";
      if (value.length < (name.startsWith("JWT_") ? 32 : 1)) {
        throw new Error(`${name} is missing or unsafe for production`);
      }
      if (unsafeProductionValues.some((unsafe) => value.includes(unsafe))) {
        throw new Error(`${name} contains a known development credential`);
      }
    }

    if (requestedMode === "PRODUCTION_APPROVED") {
      for (const name of [
        "PRODUCTION_APPROVAL_REFERENCE",
        "EXECUTION_PROVIDER_APPROVAL_REFERENCE",
      ]) {
        if (!(optionalString(input[name]) ?? "").trim()) {
          throw new Error(`${name} is required for PRODUCTION_APPROVED`);
        }
      }
    }
  }

  return environment;
}

function boundedInteger(
  value: unknown,
  fallback: number,
  minimum: number,
  maximum: number,
): string {
  const parsed = Number(optionalString(value));
  return String(
    Number.isInteger(parsed) && parsed >= minimum && parsed <= maximum
      ? parsed
      : fallback,
  );
}
