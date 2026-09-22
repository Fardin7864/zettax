import { afterEach, describe, expect, it, vi } from "vitest";
import { ContractPriceService } from "../src/timed-contracts/contract-price.service";
afterEach(() => vi.unstubAllGlobals());
describe("expiry observation identity", () => {
  const instrument = { baseAsset: "BTC", assetClass: "CRYPTO" };
  it("requests only the closed second before expiry and keeps its exact decimal", async () => {
    const fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: () =>
        Promise.resolve([[9000, "1", "1", "1", "77123.12345678", "1", 9999]]),
    });
    vi.stubGlobal("fetch", fetch);
    const quote = await new ContractPriceService().at(
      instrument,
      new Date(10500),
    );
    expect(String(fetch.mock.calls[0]?.[0])).toContain(
      "startTime=9000&endTime=9999",
    );
    expect(quote.price.toFixed()).toBe("77123.12345678");
    expect(quote.timestamp.getTime()).toBe(9999);
  });
  it("rejects a later price rather than substituting it", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        json: () =>
          Promise.resolve([[10000, "1", "1", "1", "100", "1", 10999]]),
      }),
    );
    await expect(
      new ContractPriceService().at(instrument, new Date(10500)),
    ).rejects.toMatchObject({ code: "CONTRACT_PRICE_UNAVAILABLE" });
  });
  it("keeps missing data unresolved", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("offline")));
    await expect(
      new ContractPriceService().at(instrument, new Date(10500)),
    ).rejects.toMatchObject({ code: "CONTRACT_PRICE_UNAVAILABLE" });
  });
  it("shares simultaneous requests for the same observation", async () => {
    const fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve([[9000, "1", "1", "1", "100", "1", 9999]]),
    });
    vi.stubGlobal("fetch", fetch);
    const service = new ContractPriceService();
    await Promise.all(
      Array.from({ length: 50 }, () => service.at(instrument, new Date(10500))),
    );
    expect(fetch).toHaveBeenCalledTimes(1);
  });
  it("retries the identical timestamp after publication lag", async () => {
    const fetch = vi
      .fn()
      .mockResolvedValueOnce({ ok: true, json: () => Promise.resolve([]) })
      .mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve([[9000, "1", "1", "1", "100", "1", 9999]]),
      });
    vi.stubGlobal("fetch", fetch);
    await new ContractPriceService().at(instrument, new Date(10500));
    expect(fetch.mock.calls[0]?.[0]).toBe(fetch.mock.calls[1]?.[0]);
  });
  it("rejects instruments without an approved source", async () => {
    await expect(
      new ContractPriceService().at(
        { baseAsset: "EUR", assetClass: "FOREX" },
        new Date(),
      ),
    ).rejects.toMatchObject({ code: "CONTRACT_PRICE_UNAVAILABLE" });
  });
});
