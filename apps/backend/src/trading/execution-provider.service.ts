import { HttpStatus, Injectable } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { ApiErrorException } from "../http/api-error";
import {
  ComplianceService,
  type FeatureName,
} from "../compliance/compliance.service";
import type {
  ExecutionAssetClass,
  ExecutionProvider,
  ProviderTradingStatus,
} from "./execution-provider";
import { MockExecutionProvider } from "./mock-execution.provider";

const featureByAssetClass: Record<ExecutionAssetClass, FeatureName> = {
  CRYPTO: "CRYPTO_TRADING",
  FOREX: "FOREX_TRADING",
  STOCK: "STOCK_TRADING",
  COMMODITY: "COMMODITY_TRADING",
  INDEX: "INDEX_TRADING",
};

@Injectable()
export class ExecutionProviderService {
  constructor(
    private readonly config: ConfigService,
    private readonly compliance: ComplianceService,
    private readonly mock: MockExecutionProvider,
  ) {}

  providerForDemo(): ExecutionProvider {
    return this.mock;
  }

  providerForReal(assetClass: ExecutionAssetClass): ExecutionProvider {
    if (
      !this.compliance.isEnabled("REAL_TRADING") ||
      !this.compliance.isEnabled(featureByAssetClass[assetClass])
    ) {
      throw new ApiErrorException(
        "REAL_TRADING_NOT_APPROVED",
        "Real-money trading is not approved for this product.",
        HttpStatus.FORBIDDEN,
      );
    }

    const configured = (this.config.get<string>("EXECUTION_PROVIDER") ?? "MOCK")
      .trim()
      .toUpperCase();
    if (configured === "MOCK") {
      throw new ApiErrorException(
        "PROVIDER_UNAVAILABLE",
        "No approved real-money execution adapter is installed.",
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }

    // A legitimate provider must be implemented as a separately reviewed adapter.
    // Unknown names are never treated as proof of an integration.
    throw new ApiErrorException(
      "PROVIDER_UNAVAILABLE",
      "The configured execution adapter is not registered.",
      HttpStatus.SERVICE_UNAVAILABLE,
    );
  }

  async publicStatus(): Promise<{
    demo: ProviderTradingStatus;
    real: ProviderTradingStatus;
  }> {
    const virtual = this.compliance.isVirtual;
    return {
      demo: await this.mock.getTradingStatus(),
      real: virtual
        ? {
            available: true,
            provider: "PRIMEVEST_VIRTUAL",
            environment: "SANDBOX",
            supportsRealMoney: false,
            reason: "Virtual balance simulation; no real money is routed",
          }
        : {
            available: false,
            provider: "NONE",
            environment: "PRODUCTION",
            supportsRealMoney: false,
            reason: "No approved production execution adapter is installed",
          },
    };
  }
}
