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
import { AuthService } from "../auth/auth.service";
import type { AuthenticatedPrincipal } from "../auth/auth.types";
import { AccountEventsService } from "./account-events.service";

type AccountSocket = Omit<Socket, "data"> & {
  data: {
    principal?: AuthenticatedPrincipal;
    lastSequence?: bigint;
  };
};

@WebSocketGateway({
  namespace: "/account",
  cors: {
    origin: (process.env.CORS_ORIGINS ?? "http://localhost:3001").split(","),
    credentials: true,
  },
  transports: ["websocket"],
})
export class AccountRealtimeGateway
  implements OnGatewayConnection, OnGatewayDisconnect
{
  @WebSocketServer()
  private server!: Server;

  private readonly clients = new Map<string, AccountSocket>();
  private polling = false;
  private pollTimer: NodeJS.Timeout | undefined;

  constructor(
    private readonly auth: AuthService,
    private readonly events: AccountEventsService,
  ) {}

  async handleConnection(client: AccountSocket): Promise<void> {
    const token = accessToken(client);
    if (!token) return this.reject(client, "AUTH_REQUIRED");
    let principal: AuthenticatedPrincipal;
    try {
      principal = await this.auth.validateAccessToken(token);
    } catch {
      return this.reject(client, "AUTH_SESSION_EXPIRED");
    }
    client.data.principal = principal;
    try {
      const handshakeAuth: unknown = client.handshake.auth;
      const rawSequence = isRecord(handshakeAuth)
        ? handshakeAuth["afterSequence"]
        : undefined;
      const requested = parseSequence(rawSequence);
      const latest = await this.events.latestSequence(principal.userId);
      let deliveredSequence = latest;
      if (
        rawSequence !== undefined &&
        rawSequence !== null &&
        requested === null
      ) {
        client.emit("account:error", accountError("ACCOUNT_SEQUENCE_INVALID"));
        client.emit(
          "account:snapshot",
          await this.events.snapshot(principal.userId),
        );
      } else if (requested !== null && requested <= latest) {
        const recovered = await this.events.recover(
          principal.userId,
          requested,
        );
        deliveredSequence = recovered.length
          ? BigInt(recovered.at(-1)!.sequence)
          : requested;
        client.emit("account:recovery", {
          schemaVersion: 1,
          afterSequence: requested.toString(),
          latestSequence: latest.toString(),
          events: recovered,
          complete:
            recovered.length === 0 ||
            BigInt(recovered.at(-1)!.sequence) === latest,
        });
      } else {
        if (requested !== null && requested > latest) {
          client.emit(
            "account:error",
            accountError("ACCOUNT_SEQUENCE_INVALID"),
          );
        }
        client.emit(
          "account:snapshot",
          await this.events.snapshot(principal.userId),
        );
      }
      client.data.lastSequence = deliveredSequence;
      this.clients.set(client.id, client);
      this.ensurePolling();
      client.emit("account:ready", {
        schemaVersion: 1,
        sequence: deliveredSequence.toString(),
        serverTime: new Date().toISOString(),
      });
    } catch {
      this.reject(client, "ACCOUNT_STREAM_UNAVAILABLE");
    }
  }

  handleDisconnect(client: AccountSocket): void {
    this.clients.delete(client.id);
    if (this.clients.size === 0 && this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = undefined;
    }
  }

  @SubscribeMessage("account:recover")
  async recover(
    @ConnectedSocket() client: AccountSocket,
    @MessageBody() body: { afterSequence?: unknown },
  ) {
    const principal = client.data.principal;
    if (!principal) return accountError("AUTH_REQUIRED");
    const after = parseSequence(body.afterSequence);
    if (after === null) return accountError("ACCOUNT_SEQUENCE_INVALID");
    const latest = await this.events.latestSequence(principal.userId);
    if (after > latest) return accountError("ACCOUNT_SEQUENCE_INVALID");
    const events = await this.events.recover(principal.userId, after);
    const delivered = events.at(-1)?.sequence;
    if (delivered) client.data.lastSequence = BigInt(delivered);
    return {
      ok: true,
      schemaVersion: 1,
      afterSequence: after.toString(),
      latestSequence: latest.toString(),
      events,
      complete:
        events.length === 0 || BigInt(events.at(-1)!.sequence) === latest,
    };
  }

  private ensurePolling(): void {
    if (this.pollTimer) return;
    this.pollTimer = setInterval(() => void this.poll(), 500);
    this.pollTimer.unref();
  }

  private async poll(): Promise<void> {
    if (this.polling || this.clients.size === 0) return;
    this.polling = true;
    try {
      await Promise.all(
        [...this.clients.values()].map(async (client) => {
          const principal = client.data.principal;
          if (!principal) return;
          const after = client.data.lastSequence ?? 0n;
          const events = await this.events.recover(
            principal.userId,
            after,
            100,
          );
          for (const event of events) client.emit("account:event", event);
          const delivered = events.at(-1)?.sequence;
          if (delivered) client.data.lastSequence = BigInt(delivered);
          if (events.length === 100) {
            client.emit("account:status", {
              schemaVersion: 1,
              state: "RECOVERING",
              afterSequence: (client.data.lastSequence ?? after).toString(),
            });
          }
        }),
      );
    } finally {
      this.polling = false;
    }
  }

  private reject(client: AccountSocket, code: string): void {
    client.emit("account:error", accountError(code));
    client.disconnect(true);
  }
}

export function parseSequence(value: unknown): bigint | null {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value !== "string" || !/^\d{1,19}$/.test(value)) return null;
  try {
    const parsed = BigInt(value);
    return parsed >= 0n ? parsed : null;
  } catch {
    return null;
  }
}

function accessToken(client: AccountSocket): string | null {
  const authentication: unknown = client.handshake.auth;
  const value: unknown = isRecord(authentication)
    ? authentication["token"]
    : undefined;
  if (typeof value === "string" && value.length > 0) return value;
  const authorization = client.handshake.headers.authorization;
  return authorization?.startsWith("Bearer ")
    ? authorization.slice("Bearer ".length)
    : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function accountError(code: string) {
  return { ok: false, schemaVersion: 1, code };
}
