import { Injectable } from "@nestjs/common";
import { createHash } from "node:crypto";
import type {
  ExecutionOrderRequest,
  ExecutionProvider,
  ProviderExecution,
  ProviderOrder,
  ProviderTradingStatus,
} from "./execution-provider";

@Injectable()
export class MockExecutionProvider implements ExecutionProvider {
  readonly name = "MOCK";
  readonly supportsRealMoney = false;
  private readonly orders = new Map<string, ProviderOrder>();

  validateInstrument(symbol: string): Promise<boolean> {
    return Promise.resolve(symbol.trim().length > 0);
  }

  getTradingStatus(): Promise<ProviderTradingStatus> {
    return Promise.resolve({
      available: true,
      provider: this.name,
      environment: "SIMULATION",
      supportsRealMoney: false,
      reason: "Internal deterministic simulation; never routes real money",
    });
  }

  placeOrder(request: ExecutionOrderRequest): Promise<ProviderOrder> {
    if (request.accountMode !== "DEMO") {
      throw new Error("MockExecutionProvider refuses non-demo orders");
    }
    const existing = [...this.orders.values()].find(
      (order) => order.clientOrderId === request.clientOrderId,
    );
    if (existing) return Promise.resolve(existing);

    const id = createHash("sha256")
      .update(`${request.accountId}:${request.clientOrderId}`)
      .digest("hex")
      .slice(0, 24);
    const order: ProviderOrder = {
      providerOrderId: `mock_${id}`,
      clientOrderId: request.clientOrderId,
      status: request.orderType === "MARKET" ? "FILLED" : "ACCEPTED",
      provider: this.name,
      simulated: true,
    };
    this.orders.set(order.providerOrderId, order);
    return Promise.resolve(order);
  }

  async cancelOrder(providerOrderId: string): Promise<ProviderOrder> {
    const order = await this.getOrder(providerOrderId);
    if (!order) throw new Error("Mock order was not found");
    const cancelled = { ...order, status: "CANCELLED" as const };
    this.orders.set(providerOrderId, cancelled);
    return cancelled;
  }

  getOrder(providerOrderId: string): Promise<ProviderOrder | null> {
    return Promise.resolve(this.orders.get(providerOrderId) ?? null);
  }

  async getExecutions(
    providerOrderId: string,
  ): Promise<readonly ProviderExecution[]> {
    const order = await this.getOrder(providerOrderId);
    return order?.status === "FILLED"
      ? [{ providerOrderId, simulated: true }]
      : [];
  }

  getPosition(instrumentId: string): Promise<null> {
    void instrumentId;
    return Promise.resolve(null);
  }

  reconcile(): Promise<{ checkedAt: string; discrepancies: number }> {
    return Promise.resolve({
      checkedAt: new Date().toISOString(),
      discrepancies: 0,
    });
  }
}
