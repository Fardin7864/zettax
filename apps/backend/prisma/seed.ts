import {
  AssetClass,
  PaymentAccountType,
  PaymentMethodType,
  Prisma,
  PrismaClient,
} from "@prisma/client";
import { instruments as displayInstruments } from "../src/markets/instruments";

const prisma = new PrismaClient();

const instrumentCatalogue = [
  [
    "10000000-0000-4000-8000-000000000001",
    "btc-usd",
    "BTC/USD",
    "Bitcoin",
    AssetClass.CRYPTO,
    "BTC",
    "USD",
    2,
    8,
  ],
  [
    "10000000-0000-4000-8000-000000000002",
    "eth-usd",
    "ETH/USD",
    "Ethereum",
    AssetClass.CRYPTO,
    "ETH",
    "USD",
    2,
    8,
  ],
  [
    "10000000-0000-4000-8000-000000000003",
    "sol-usd",
    "SOL/USD",
    "Solana",
    AssetClass.CRYPTO,
    "SOL",
    "USD",
    3,
    6,
  ],
  [
    "10000000-0000-4000-8000-000000000004",
    "xrp-usd",
    "XRP/USD",
    "XRP",
    AssetClass.CRYPTO,
    "XRP",
    "USD",
    5,
    4,
  ],
  [
    "10000000-0000-4000-8000-000000000005",
    "eur-usd",
    "EUR/USD",
    "Euro / US Dollar",
    AssetClass.FOREX,
    "EUR",
    "USD",
    5,
    2,
  ],
  [
    "10000000-0000-4000-8000-000000000006",
    "gbp-usd",
    "GBP/USD",
    "British Pound / US Dollar",
    AssetClass.FOREX,
    "GBP",
    "USD",
    5,
    2,
  ],
  [
    "10000000-0000-4000-8000-000000000007",
    "usd-jpy",
    "USD/JPY",
    "US Dollar / Japanese Yen",
    AssetClass.FOREX,
    "USD",
    "JPY",
    3,
    2,
  ],
  [
    "10000000-0000-4000-8000-000000000008",
    "aud-usd",
    "AUD/USD",
    "Australian Dollar / US Dollar",
    AssetClass.FOREX,
    "AUD",
    "USD",
    5,
    2,
  ],
  [
    "10000000-0000-4000-8000-000000000009",
    "aapl",
    "AAPL",
    "Apple",
    AssetClass.STOCK,
    "AAPL",
    "USD",
    2,
    4,
  ],
  [
    "10000000-0000-4000-8000-000000000010",
    "msft",
    "MSFT",
    "Microsoft",
    AssetClass.STOCK,
    "MSFT",
    "USD",
    2,
    4,
  ],
  [
    "10000000-0000-4000-8000-000000000011",
    "nvda",
    "NVDA",
    "NVIDIA",
    AssetClass.STOCK,
    "NVDA",
    "USD",
    2,
    4,
  ],
  [
    "10000000-0000-4000-8000-000000000012",
    "spx",
    "S&P 500",
    "S&P 500 Index",
    AssetClass.INDEX,
    "SPX",
    "USD",
    2,
    4,
  ],
  [
    "10000000-0000-4000-8000-000000000013",
    "ndx",
    "NASDAQ 100",
    "NASDAQ 100 Index",
    AssetClass.INDEX,
    "NDX",
    "USD",
    2,
    4,
  ],
  [
    "10000000-0000-4000-8000-000000000014",
    "xau-usd",
    "XAU/USD",
    "Gold",
    AssetClass.COMMODITY,
    "XAU",
    "USD",
    2,
    4,
  ],
  [
    "10000000-0000-4000-8000-000000000015",
    "xag-usd",
    "XAG/USD",
    "Silver",
    AssetClass.COMMODITY,
    "XAG",
    "USD",
    3,
    4,
  ],
] as const;

const featureFlags = [
  ["ENABLE_REAL_TRADING", false, "Global server-side real trading gate"],
  ["ENABLE_CRYPTO_TRADING", false, "Real crypto price-instrument gate"],
  ["ENABLE_FOREX_TRADING", false, "Real forex gate"],
  ["ENABLE_STOCK_TRADING", false, "Real stock gate"],
  ["ENABLE_COMMODITY_TRADING", false, "Real commodity gate"],
  ["ENABLE_INDEX_TRADING", false, "Real index gate"],
  [
    "ENABLE_TIMED_TRADING",
    true,
    "Demo timed-direction gate; real remains separately gated",
  ],
  ["ENABLE_DEPOSITS", false, "Real manual deposit gate"],
  ["ENABLE_WITHDRAWALS", false, "Real manual withdrawal gate"],
] as const;

async function seed(): Promise<void> {
  await prisma.currency.upsert({
    where: { code: "BDT" },
    update: { name: "Bangladeshi Taka", precision: 2 },
    create: { code: "BDT", name: "Bangladeshi Taka", precision: 2 },
  });
  await prisma.currency.upsert({
    where: { code: "USD" },
    update: { name: "US Dollar", precision: 2 },
    create: { code: "USD", name: "US Dollar", precision: 2 },
  });

  await prisma.complianceConfig.upsert({
    where: { id: "active" },
    update: {},
    create: {
      id: "active",
      mode: "DEMO_ONLY",
      config: { source: "database-seed", productionApproved: false },
    },
  });

  for (const [key, enabled, description] of featureFlags) {
    await prisma.featureFlag.upsert({
      where: { key },
      update: { description },
      create: { key, enabled, description },
    });
  }

  await prisma.systemConfig.upsert({
    where: { key: "execution.provider" },
    update: {},
    create: {
      key: "execution.provider",
      value: { name: "MOCK", supportsRealMoney: false },
    },
  });

  const paymentMethods = [
    {
      id: "20000000-0000-4000-8000-000000000001",
      type: PaymentMethodType.BKASH,
      displayName: "bKash",
    },
    {
      id: "20000000-0000-4000-8000-000000000002",
      type: PaymentMethodType.NAGAD,
      displayName: "Nagad",
    },
    {
      id: "20000000-0000-4000-8000-000000000003",
      type: PaymentMethodType.ROCKET,
      displayName: "Rocket",
    },
  ] as const;
  for (const method of paymentMethods) {
    const values = {
      type: method.type,
      displayName: method.displayName,
      accountNumber: "01885482244",
      accountType: PaymentAccountType.PERSONAL,
      instructions: `Send Money to this personal ${method.displayName} number, then submit the exact amount, sender number, transaction ID, and payment screenshot.`,
      minimumDeposit: new Prisma.Decimal("100.00"),
      maximumDeposit: new Prisma.Decimal("100000.00"),
      feeType: "NONE",
      feeValue: new Prisma.Decimal("0"),
      isEnabled: true,
    };
    await prisma.paymentMethod.upsert({
      where: { id: method.id },
      update: {},
      create: { id: method.id, ...values },
    });
  }

  for (const [
    id,
    slug,
    symbol,
    name,
    assetClass,
    baseAsset,
    quoteAsset,
    pricePrecision,
    quantityPrecision,
  ] of instrumentCatalogue) {
    const instrument = await prisma.instrument.upsert({
      where: { slug },
      update: {
        symbol,
        name,
        assetClass,
        baseAsset,
        quoteAsset,
        pricePrecision,
        quantityPrecision,
      },
      create: {
        id,
        slug,
        symbol,
        name,
        assetClass,
        baseAsset,
        quoteAsset,
        pricePrecision,
        quantityPrecision,
        marketStatus: "SIMULATED",
        demoEnabled: true,
        realEnabled: false,
      },
    });
    await prisma.instrumentConfig.upsert({
      where: { instrumentId: instrument.id },
      update: {},
      create: {
        instrumentId: instrument.id,
        minimumTrade: new Prisma.Decimal("1"),
        maximumTrade: new Prisma.Decimal("100000"),
        spreadBps: assetClass === AssetClass.FOREX ? 2 : 10,
        maxQuoteAgeMs: 5000,
      },
    });
  }
  for (const item of displayInstruments.filter(
    (entry) => entry.assetClass === "CRYPTO" &&
      !["btc-usd", "eth-usd", "sol-usd", "xrp-usd"].includes(entry.id),
  )) {
    const instrument = await prisma.instrument.upsert({
      where: { slug: item.id },
      update: {},
      create: {
        slug: item.id,
        symbol: item.symbol,
        name: item.name,
        assetClass: AssetClass.CRYPTO,
        baseAsset: item.baseAsset,
        quoteAsset: item.quoteAsset,
        pricePrecision: item.pricePrecision,
        quantityPrecision: item.quantityPrecision,
      },
    });
    await prisma.instrumentConfig.upsert({
      where: { instrumentId: instrument.id },
      update: {},
      create: {
        instrumentId: instrument.id,
        minimumTrade: new Prisma.Decimal("1"),
        maximumTrade: new Prisma.Decimal("100000"),
        spreadBps: 10,
      },
    });
  }
}

seed()
  .then(() => prisma.$disconnect())
  .catch(async (error: unknown) => {
    console.error("Database seed failed", error);
    await prisma.$disconnect();
    process.exitCode = 1;
  });
