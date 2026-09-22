export type ExecutionAccountMode = "DEMO" | "REAL";
export type ExecutionAssetClass =
  "CRYPTO" | "FOREX" | "STOCK" | "COMMODITY" | "INDEX";
export type ExecutionOrderSide = "BUY" | "SELL";
export type ExecutionOrderType = "MARKET" | "LIMIT" | "STOP" | "STOP_LIMIT";

export type ExecutionOrderRequest = {
  clientOrderId: string;
  accountId: string;
  accountMode: ExecutionAccountMode;
  instrumentId: string;
  symbol: string;
  assetClass: ExecutionAssetClass;
  side: ExecutionOrderSide;
  orderType: ExecutionOrderType;
  quantity: string;
  limitPrice?: string;
  stopPrice?: string;
};

export type ProviderOrder = {
  providerOrderId: string;
  clientOrderId: string;
  status: "ACCEPTED" | "FILLED" | "CANCELLED" | "REJECTED";
  provider: string;
  simulated: boolean;
};

export type ProviderTradingStatus = {
  available: boolean;
  provider: string;
  environment: "SIMULATION" | "SANDBOX" | "PRODUCTION";
  supportsRealMoney: boolean;
  reason?: string;
};

export type ProviderExecution = {
  providerOrderId: string;
  simulated: boolean;
};

export type ProviderPosition = {
  instrumentId: string;
  quantity: string;
};

export interface ExecutionProvider {
  readonly name: string;
  readonly supportsRealMoney: boolean;
  validateInstrument(symbol: string): Promise<boolean>;
  getTradingStatus(): Promise<ProviderTradingStatus>;
  placeOrder(request: ExecutionOrderRequest): Promise<ProviderOrder>;
  cancelOrder(providerOrderId: string): Promise<ProviderOrder>;
  getOrder(providerOrderId: string): Promise<ProviderOrder | null>;
  getExecutions(providerOrderId: string): Promise<readonly ProviderExecution[]>;
  getPosition(instrumentId: string): Promise<ProviderPosition | null>;
  reconcile(): Promise<{ checkedAt: string; discrepancies: number }>;
}
