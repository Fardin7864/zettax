import { ConfigService } from "@nestjs/config";
import { describe, expect, it } from "vitest";
import { ComplianceService } from "../src/compliance/compliance.service";

function service(values: Record<string, string>): ComplianceService {
  return new ComplianceService(new ConfigService(values));
}

describe("ComplianceService", () => {
  it("fails closed for every real-money feature in demo mode", () => {
    const compliance = service({
      COMPLIANCE_MODE: "DEMO_ONLY",
      ENABLE_REAL_TRADING: "true",
      ENABLE_CRYPTO_TRADING: "true",
      ENABLE_DEPOSITS: "true",
    });
    expect(compliance.isEnabled("CRYPTO_TRADING")).toBe(false);
    expect(compliance.isEnabled("DEPOSITS")).toBe(false);
  });

  it("requires both production approval and global real trading", () => {
    const compliance = service({
      COMPLIANCE_MODE: "PRODUCTION_APPROVED",
      ENABLE_REAL_TRADING: "false",
      ENABLE_CRYPTO_TRADING: "true",
    });
    expect(compliance.isEnabled("CRYPTO_TRADING")).toBe(false);
  });

  it("allows demo engines without enabling real money", () => {
    expect(
      service({ COMPLIANCE_MODE: "DEMO_ONLY" }).isEnabled(
        "TIMED_TRADING",
        "DEMO",
      ),
    ).toBe(true);
  });

  it("enables explicitly flagged virtual account features in sandbox mode", () => {
    const compliance = service({
      COMPLIANCE_MODE: "SANDBOX",
      ENABLE_REAL_TRADING: "true",
      ENABLE_DEPOSITS: "true",
      ENABLE_WITHDRAWALS: "true",
    });
    expect(compliance.isVirtual).toBe(true);
    expect(compliance.isEnabled("REAL_TRADING")).toBe(true);
    expect(compliance.isEnabled("DEPOSITS")).toBe(true);
    expect(compliance.isEnabled("WITHDRAWALS")).toBe(true);
    expect(compliance.publicConfig().real.fundsKind).toBe("VIRTUAL");
  });
});
