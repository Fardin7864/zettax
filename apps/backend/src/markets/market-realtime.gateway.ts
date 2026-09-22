import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  OnGatewayDisconnect,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from "@nestjs/websockets";
import type { Server, Socket } from "socket.io";
import WebSocket, { type RawData } from "ws";
import { AuthService } from "../auth/auth.service";
import type { AuthenticatedPrincipal } from "../auth/auth.types";
import { instruments, type SeedInstrument } from "./instruments";
import {
  MARKET_INTERVALS,
  type Candle,
  type MarketInterval,
} from "./market-data.provider";

type SubscribeRequest = { instrumentId?: unknown; interval?: unknown };
type AuthenticatedSocket = Omit<Socket, "data"> & {
  data: { principal?: AuthenticatedPrincipal };
};

type StreamState = {
  key: string;
  room: string;
  instrument: SeedInstrument;
  interval: MarketInterval;
  sourceSymbol: string;
  subscribers: Set<string>;
  socket: WebSocket | null;
  reconnectTimer: NodeJS.Timeout | null;
  reconnectAttempts: number;
  sequence: bigint;
  stopped: boolean;
};

type BinanceKlineEvent = {
  e?: unknown;
  E?: unknown;
  k?: {
    t?: unknown;
    T?: unknown;
    o?: unknown;
    h?: unknown;
    l?: unknown;
    c?: unknown;
    v?: unknown;
    x?: unknown;
  };
};

export type NormalizedRealtimeCandle = {
  schemaVersion: 1;
  sequence: string;
  instrumentId: string;
  interval: MarketInterval;
  providerId: "BINANCE_PUBLIC_SPOT";
  provider: "Binance Public Spot";
  sourceSymbol: string;
  freshness: "DISPLAY_LIVE";
  providerTimestamp: string;
  receivedAt: string;
  executionPrice: false;
  executionEligible: false;
  final: boolean;
  candle: Candle;
};

@WebSocketGateway({
  namespace: "/market",
  cors: {
    origin: (process.env.CORS_ORIGINS ?? "http://localhost:3001").split(","),
    credentials: true,
  },
  transports: ["websocket"],
})
export class MarketRealtimeGateway
  implements OnGatewayConnection, OnGatewayDisconnect
{
  @WebSocketServer()
  private server!: Server;

  private readonly streams = new Map<string, StreamState>();
  private readonly clientStreams = new Map<string, string>();

  constructor(private readonly auth: AuthService) {}

  async handleConnection(client: AuthenticatedSocket): Promise<void> {
    const token = this.accessToken(client);
    if (!token) {
      client.emit("market:ready", {
        schemaVersion: 1,
        access: "PUBLIC",
        serverTime: new Date().toISOString(),
      });
      return;
    }
    try {
      client.data.principal = await this.auth.validateAccessToken(token);
      client.emit("market:ready", {
        schemaVersion: 1,
        access: "AUTHENTICATED",
        serverTime: new Date().toISOString(),
      });
    } catch {
      client.emit("market:error", this.error("AUTH_SESSION_EXPIRED"));
      client.disconnect(true);
    }
  }

  handleDisconnect(client: AuthenticatedSocket): void {
    this.releaseClient(client.id, client);
  }

  @SubscribeMessage("market:subscribe")
  subscribe(
    @ConnectedSocket() client: AuthenticatedSocket,
    @MessageBody() request: SubscribeRequest,
  ) {
    const instrumentId =
      typeof request.instrumentId === "string" ? request.instrumentId : "";
    const interval =
      typeof request.interval === "string" ? request.interval : "";
    const instrument = instruments.find((item) => item.id === instrumentId);
    if (!instrument) return this.error("INSTRUMENT_NOT_FOUND");
    if (!MARKET_INTERVALS.includes(interval as MarketInterval)) {
      return this.error("UNSUPPORTED_INTERVAL");
    }
    if (instrument.assetClass !== "CRYPTO") {
      return this.error("REALTIME_CAPABILITY_UNAVAILABLE");
    }

    this.releaseClient(client.id, client);
    const key = `${instrument.id}:${interval}`;
    let stream = this.streams.get(key);
    let created = false;
    if (!stream) {
      const sourceSymbol = `${instrument.baseAsset}${
        instrument.quoteAsset === "USD" ? "USDT" : instrument.quoteAsset
      }`;
      stream = {
        key,
        room: `market:${key}`,
        instrument,
        interval: interval as MarketInterval,
        sourceSymbol,
        subscribers: new Set(),
        socket: null,
        reconnectTimer: null,
        reconnectAttempts: 0,
        sequence: 0n,
        stopped: false,
      };
      this.streams.set(key, stream);
      created = true;
    }
    stream.subscribers.add(client.id);
    this.clientStreams.set(client.id, key);
    void client.join(stream.room);
    if (created) this.connectProvider(stream);
    return {
      ok: true,
      schemaVersion: 1,
      instrumentId,
      interval,
      sourceSymbol: stream.sourceSymbol,
    };
  }

  @SubscribeMessage("market:unsubscribe")
  unsubscribe(@ConnectedSocket() client: AuthenticatedSocket) {
    this.releaseClient(client.id, client);
    return { ok: true, schemaVersion: 1 };
  }

  private connectProvider(stream: StreamState): void {
    if (stream.stopped || stream.subscribers.size === 0) return;
    const path = `${stream.sourceSymbol.toLowerCase()}@kline_${stream.interval}`;
    const socket = new WebSocket(
      `wss://stream.binance.com:9443/ws/${encodeURIComponent(path)}`,
      { handshakeTimeout: 8_000 },
    );
    stream.socket = socket;

    socket.on("open", () => {
      stream.reconnectAttempts = 0;
      this.server.to(stream.room).emit("market:status", {
        schemaVersion: 1,
        state: "CONNECTED",
        instrumentId: stream.instrument.id,
        interval: stream.interval,
        serverTime: new Date().toISOString(),
      });
    });
    socket.on("message", (data: RawData) => {
      const event = parseBinanceKline(
        rawDataToText(data),
        stream,
        ++stream.sequence,
      );
      if (event) this.server.to(stream.room).emit("market:candle", event);
    });
    socket.on("ping", (data) => socket.pong(data));
    socket.on("error", () => {
      // Close drives the bounded reconnect path; error details are never sent.
    });
    socket.on("close", () => {
      if (stream.socket === socket) stream.socket = null;
      if (stream.stopped || stream.subscribers.size === 0) return;
      this.server.to(stream.room).emit("market:status", {
        schemaVersion: 1,
        state: "RECONNECTING",
        instrumentId: stream.instrument.id,
        interval: stream.interval,
        serverTime: new Date().toISOString(),
      });
      const attempt = Math.min(stream.reconnectAttempts++, 6);
      const delay =
        Math.min(30_000, 1_000 * 2 ** attempt) +
        Math.floor(Math.random() * 500);
      stream.reconnectTimer = setTimeout(
        () => this.connectProvider(stream),
        delay,
      );
    });
  }

  private releaseClient(clientId: string, client?: AuthenticatedSocket): void {
    const key = this.clientStreams.get(clientId);
    if (!key) return;
    this.clientStreams.delete(clientId);
    const stream = this.streams.get(key);
    if (!stream) return;
    void client?.leave(stream.room);
    stream.subscribers.delete(clientId);
    if (stream.subscribers.size > 0) return;
    stream.stopped = true;
    if (stream.reconnectTimer) clearTimeout(stream.reconnectTimer);
    stream.socket?.close(1000, "No subscribers");
    this.streams.delete(key);
  }

  private accessToken(client: AuthenticatedSocket): string | null {
    const authentication: unknown = client.handshake.auth;
    const authToken = isRecord(authentication)
      ? authentication["token"]
      : undefined;
    if (typeof authToken === "string" && authToken.length > 0) return authToken;
    const authorization = client.handshake.headers.authorization;
    if (authorization?.startsWith("Bearer ")) {
      return authorization.slice("Bearer ".length);
    }
    return null;
  }

  private error(code: string) {
    return { ok: false, schemaVersion: 1, code };
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function rawDataToText(data: RawData): string {
  if (Array.isArray(data)) return Buffer.concat(data).toString("utf8");
  if (data instanceof ArrayBuffer) return Buffer.from(data).toString("utf8");
  return data.toString("utf8");
}

export function parseBinanceKline(
  raw: string,
  stream: Pick<StreamState, "instrument" | "interval" | "sourceSymbol">,
  sequence: bigint,
): NormalizedRealtimeCandle | null {
  let payload: BinanceKlineEvent;
  try {
    payload = JSON.parse(raw) as BinanceKlineEvent;
  } catch {
    return null;
  }
  const kline = payload.k;
  if (payload.e !== "kline" || !kline) return null;
  const decimal = /^\d+(?:\.\d+)?$/;
  const values = [kline.o, kline.h, kline.l, kline.c, kline.v];
  if (
    !values.every((value) => typeof value === "string" && decimal.test(value))
  ) {
    return null;
  }
  const openTime = new Date(Number(kline.t));
  const closeTime = new Date(Number(kline.T));
  const providerTime = new Date(Number(payload.E));
  if (
    !Number.isFinite(openTime.getTime()) ||
    !Number.isFinite(closeTime.getTime()) ||
    !Number.isFinite(providerTime.getTime()) ||
    closeTime <= openTime
  ) {
    return null;
  }
  const low = Number(kline.l);
  const high = Number(kline.h);
  const open = Number(kline.o);
  const close = Number(kline.c);
  if (low > high || open < low || open > high || close < low || close > high) {
    return null;
  }
  return {
    schemaVersion: 1,
    sequence: sequence.toString(),
    instrumentId: stream.instrument.id,
    interval: stream.interval,
    providerId: "BINANCE_PUBLIC_SPOT",
    provider: "Binance Public Spot",
    sourceSymbol: stream.sourceSymbol,
    freshness: "DISPLAY_LIVE",
    providerTimestamp: providerTime.toISOString(),
    receivedAt: new Date().toISOString(),
    executionPrice: false,
    executionEligible: false,
    final: kline.x === true,
    candle: {
      openTime: openTime.toISOString(),
      closeTime: closeTime.toISOString(),
      open: String(kline.o),
      high: String(kline.h),
      low: String(kline.l),
      close: String(kline.c),
      volume: String(kline.v),
    },
  };
}
