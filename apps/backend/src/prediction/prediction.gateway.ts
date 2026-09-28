import { WebSocketGateway, WebSocketServer } from "@nestjs/websockets";
import type { Server } from "socket.io";
import type { OnModuleDestroy } from "@nestjs/common";
import { PrismaService } from "../database/prisma.service";

@WebSocketGateway({
  namespace: "/prediction",
  cors: {
    origin: (process.env.CORS_ORIGINS ?? "http://localhost:3001").split(","),
  },
  transports: ["websocket"],
})
export class PredictionGateway implements OnModuleDestroy {
  @WebSocketServer() private server!: Server;
  constructor(private readonly prisma: PrismaService) {}
  private timer?: ReturnType<typeof setInterval>;
  private version = "";
  private checking = false;
  afterInit() {
    // Worker settlements happen in a different process. Observe committed changes.
    this.timer = setInterval(() => void this.checkUpdates(), 2000);
    this.timer.unref();
  }
  onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
  }
  private async checkUpdates() {
    if (this.checking) return;
    this.checking = true;
    try {
      const state = await this.prisma.predictionQuestion.aggregate({
        _max: { updatedAt: true },
        _count: { id: true },
      });
      const version = `${state._count.id}:${state._max.updatedAt?.toISOString()}`;
      if (version !== this.version) {
        this.version = version;
        this.server?.emit("prediction:sync", { version });
      }
    } catch {
      /* Clients also reconcile periodically and after reconnecting. */
    } finally {
      this.checking = false;
    }
  }

  created(id: string) {
    this.server?.emit("prediction:created", { id });
  }

  changed(id: string) {
    this.server?.emit("prediction:changed", { id });
  }
}
