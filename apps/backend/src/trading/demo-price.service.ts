import { Injectable } from "@nestjs/common";
import { OrderSide, Prisma, type Instrument } from "@prisma/client";
import { createHash } from "node:crypto";

const referencePrices: Record<string, string> = {
  "btc-usd": "111420.25",
  "eth-usd": "4328.18",
  "sol-usd": "218.42",
  "xrp-usd": "3.2145",
  "ada-usd": "0.2592",
  "doge-usd": "0.1020",
  "avax-usd": "11.226",
  "dot-usd": "1.194",
  "link-usd": "13.078",
  "ltc-usd": "64.10",
  "bch-usd": "358.30",
  "trx-usd": "0.3440",
  "uni-usd": "10.385",
  "atom-usd": "1.837",
  "near-usd": "4.510",
  "shib-usd": "0.00000617",
  "apt-usd": "0.8551",
  "sui-usd": "1.0310",
  "pepe-usd": "0.00000500",
  "eur-usd": "1.16842",
  "gbp-usd": "1.35281",
  "usd-jpy": "147.382",
  "aud-usd": "0.66218",
  aapl: "238.47",
  msft: "512.63",
  nvda: "184.92",
  spx: "6514.28",
  ndx: "23908.41",
  "xau-usd": "3642.17",
  "xag-usd": "41.382",
};

export type DemoExecutionQuote = {
  price: Prisma.Decimal;
  providerId: string;
  timestamp: Date;
};

/** Server-owned deterministic paper quote. It is never a real execution feed. */
@Injectable()
export class DemoPriceService {
  quote(
    instrument: Pick<Instrument, "slug" | "pricePrecision">,
    side: OrderSide,
    now = new Date(),
  ): DemoExecutionQuote {
    const base = new Prisma.Decimal(referencePrices[instrument.slug] ?? "1");
    const bucket = Math.floor(now.getTime() / 15_000);
    const seed = Number.parseInt(
      createHash("sha256")
        .update(`${instrument.slug}:${bucket}`)
        .digest("hex")
        .slice(0, 8),
      16,
    );
    const movementBps = (seed % 31) - 15;
    const spreadBps = side === OrderSide.BUY ? 4 : -4;
    const price = base
      .mul(new Prisma.Decimal(10_000 + movementBps + spreadBps))
      .div(10_000)
      .toDecimalPlaces(instrument.pricePrecision, Prisma.Decimal.ROUND_HALF_UP);
    return {
      price,
      providerId: `PRIMEVEST_DEMO:${bucket}`,
      timestamp: new Date(bucket * 15_000),
    };
  }

  mark(
    instrument: Pick<Instrument, "slug" | "pricePrecision">,
    now = new Date(),
  ): DemoExecutionQuote {
    const base = new Prisma.Decimal(referencePrices[instrument.slug] ?? "1");
    const bucket = Math.floor(now.getTime() / 15_000);
    const seed = Number.parseInt(
      createHash("sha256")
        .update(`${instrument.slug}:${bucket}`)
        .digest("hex")
        .slice(0, 8),
      16,
    );
    const movementBps = (seed % 31) - 15;
    return {
      price: base
        .mul(new Prisma.Decimal(10_000 + movementBps))
        .div(10_000)
        .toDecimalPlaces(
          instrument.pricePrecision,
          Prisma.Decimal.ROUND_HALF_UP,
        ),
      providerId: `PRIMEVEST_DEMO:${bucket}`,
      timestamp: new Date(bucket * 15_000),
    };
  }
}
