import { NextRequest, NextResponse } from "next/server";

const intervals = new Set([
  "1m",
  "5m",
  "15m",
  "30m",
  "1h",
  "4h",
  "1d",
  "1w",
  "1M",
]);
const apiBase = (
  process.env.MARKET_API_BASE_URL || "https://api.zettax.app/api/v1"
).replace(/\/$/, "");
const cryptoSymbols = new Set([
  "BTC",
  "ETH",
  "SOL",
  "XRP",
  "ADA",
  "DOGE",
  "AVAX",
  "DOT",
  "LINK",
  "LTC",
  "BCH",
  "TRX",
  "UNI",
  "ATOM",
  "NEAR",
  "SHIB",
  "APT",
  "SUI",
  "PEPE",
]);

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ resource: string }> },
) {
  const { resource } = await params;
  let path: string;
  let base = apiBase;
  if (resource === "instruments") {
    path = "markets/instruments";
  } else if (resource === "candles") {
    const id = request.nextUrl.searchParams.get("instrumentId") || "";
    const interval = request.nextUrl.searchParams.get("interval") || "";
    const limit = Number(request.nextUrl.searchParams.get("limit") || "90");
    if (
      !/^[a-z0-9-]{1,40}$/.test(id) ||
      !intervals.has(interval) ||
      !Number.isInteger(limit) ||
      limit < 10 ||
      limit > 200
    ) {
      return NextResponse.json(
        { message: "Invalid market request." },
        { status: 400 },
      );
    }
    path = `markets/instruments/${id}/candles?interval=${encodeURIComponent(interval)}&limit=${limit}`;
  } else if (resource === "depth" || resource === "trades") {
    const id = request.nextUrl.searchParams.get("instrumentId") || "";
    const match = /^([a-z]+)-usd$/.exec(id);
    const asset = match?.[1]?.toUpperCase() || "";
    if (!cryptoSymbols.has(asset))
      return NextResponse.json(
        {
          message: "Market depth is available for supported crypto pairs only.",
        },
        { status: 400 },
      );
    base = "https://api.binance.com";
    path = `api/v3/${resource === "depth" ? "depth" : "trades"}?symbol=${asset}USDT&limit=20`;
  } else {
    return NextResponse.json(
      { message: "Unknown market resource." },
      { status: 404 },
    );
  }

  try {
    const response = await fetch(`${base}/${path}`, {
      cache: "no-store",
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(9000),
    });
    const body = await response.json();
    return NextResponse.json(body, {
      status: response.status,
      headers: { "Cache-Control": "no-store" },
    });
  } catch {
    return NextResponse.json(
      { message: "Market data is temporarily unavailable." },
      { status: 503 },
    );
  }
}
