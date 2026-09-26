import { Injectable } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import type { ComplianceMode } from "@primevest/shared-types";

export type FeatureName =
  | "REAL_TRADING"
  | "CRYPTO_TRADING"
  | "FOREX_TRADING"
  | "STOCK_TRADING"
  | "COMMODITY_TRADING"
  | "INDEX_TRADING"
  | "TIMED_TRADING"
  | "PREDICTIONS"
  | "DEPOSITS"
  | "WITHDRAWALS";

@Injectable()
export class ComplianceService {
  constructor(private readonly config: ConfigService) {}

  get mode(): ComplianceMode {
    const value: unknown = this.config.get("COMPLIANCE_MODE");
    return value === "SANDBOX" || value === "PRODUCTION_APPROVED"
      ? value
      : "DEMO_ONLY";
  }

  /** SANDBOX uses the REAL account ledger with explicitly virtual funds. */
  get isVirtual(): boolean {
    return this.mode === "SANDBOX";
  }

  isEnabled(
    feature: FeatureName,
    accountMode: "DEMO" | "REAL" = "REAL",
  ): boolean {
    if (accountMode === "DEMO") {
      return (
        feature === "TIMED_TRADING" ||
        feature === "PREDICTIONS" ||
        feature.endsWith("_TRADING")
      );
    }

    if (this.mode === "SANDBOX") return this.flag(feature);
    if (this.mode !== "PRODUCTION_APPROVED") return false;
    if (
      feature.endsWith("_TRADING") &&
      feature !== "REAL_TRADING" &&
      !this.flag("REAL_TRADING")
    ) {
      return false;
    }
    return this.flag(feature);
  }

  publicConfig() {
    return {
      complianceMode: this.mode,
      demo: {
        enabled: true,
        initialBalanceUsd: this.stringValue(
          "DEMO_INITIAL_BALANCE_USD",
          "1000.00",
        ),
      },
      real: {
        fundsKind: this.isVirtual ? "VIRTUAL" : "REAL_MONEY",
        trading: this.isEnabled("REAL_TRADING"),
        crypto: this.isEnabled("CRYPTO_TRADING"),
        forex: this.isEnabled("FOREX_TRADING"),
        stocks: this.isEnabled("STOCK_TRADING"),
        commodities: this.isEnabled("COMMODITY_TRADING"),
        indices: this.isEnabled("INDEX_TRADING"),
        timed: this.isEnabled("TIMED_TRADING"),
        predictions: this.isEnabled("PREDICTIONS"),
        deposits: this.isEnabled("DEPOSITS"),
        withdrawals: this.isEnabled("WITHDRAWALS"),
      },
      marketData: {
        kind: "NORMALIZED_EXTERNAL_DISPLAY",
        label:
          "Server-normalized external display data; never an execution price",
      },
      serverTime: new Date().toISOString(),
    };
  }

  private flag(name: FeatureName): boolean {
    return this.stringValue(`ENABLE_${name}`, "false").toLowerCase() === "true";
  }

  private stringValue(name: string, fallback: string): string {
    const value: unknown = this.config.get(name);
    return typeof value === "string" ? value : fallback;
  }
}
