import { ConfigService } from "@nestjs/config";
import { describe, expect, it } from "vitest";
import { ComplianceService } from "../src/compliance/compliance.service";
import { ExecutionProviderService } from "../src/trading/execution-provider.service";
import { MockExecutionProvider } from "../src/trading/mock-execution.provider";
import { ApiErrorException } from "../src/http/api-error";

function providers(values: Record<string, string>): ExecutionProviderService {
  const config = new ConfigService(values);
  return new ExecutionProviderService(
    config,
    new ComplianceService(config),
    new MockExecutionProvider(),
  );
}

describe("ExecutionProviderService", () => {
  it("routes demo orders only to the explicitly simulated provider", async () => {
    const provider = providers({
      COMPLIANCE_MODE: "DEMO_ONLY",
    }).providerForDemo();
    const order = await provider.placeOrder({
      clientOrderId: "order-1",
      accountId: "demo-account",
      accountMode: "DEMO",
      instrumentId: "btc",
      symbol: "BTC/USD",
      assetClass: "CRYPTO",
      side: "BUY",
      orderType: "MARKET",
      quantity: "0.001",
    });
    expect(order.simulated).toBe(true);
    expect(order.providerOrderId).toMatch(/^mock_/);
  });

  it("rejects real trading when compliance is not production approved", () => {
    expect(() =>
      providers({
        COMPLIANCE_MODE: "DEMO_ONLY",
        ENABLE_REAL_TRADING: "true",
        ENABLE_CRYPTO_TRADING: "true",
      }).providerForReal("CRYPTO"),
    ).toThrow(
      expect.objectContaining({
        code: "REAL_TRADING_NOT_APPROVED",
        status: 403,
      }) as ApiErrorException,
    );
  });

  it("still rejects production flags when no approved adapter exists", () => {
    expect(() =>
      providers({
        COMPLIANCE_MODE: "PRODUCTION_APPROVED",
        ENABLE_REAL_TRADING: "true",
        ENABLE_CRYPTO_TRADING: "true",
        EXECUTION_PROVIDER: "MOCK",
      }).providerForReal("CRYPTO"),
    ).toThrow(
      expect.objectContaining({
        code: "PROVIDER_UNAVAILABLE",
        status: 503,
      }) as ApiErrorException,
    );
  });
});
