import { WebSocketGateway, WebSocketServer } from "@nestjs/websockets";
import type { Server } from "socket.io";

@WebSocketGateway({
  namespace: "/prediction",
  cors: {
    origin: (process.env.CORS_ORIGINS ?? "http://localhost:3001").split(","),
  },
  transports: ["websocket"],
})
export class PredictionGateway {
  @WebSocketServer() private server!: Server;

  created(id: string) {
    this.server?.emit("prediction:created", { id });
  }

  changed(id: string) {
    this.server?.emit("prediction:changed", { id });
  }
}
