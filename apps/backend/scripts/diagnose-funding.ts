import { readFileSync } from "node:fs";
import { JwtService } from "@nestjs/jwt";
import { PrismaService } from "../src/database/prisma.service";
import { validateEnvironment } from "../src/config/environment";
import { ConfigService } from "@nestjs/config";
import { EvidenceService } from "../src/funding/evidence.service";
import { io } from "socket.io-client";

async function main() {
  const input: Record<string, string> = { NODE_ENV: "development" };
  for (const line of readFileSync("../../.env.local", "utf8").split(/\r?\n/)) {
    const match = /^([^#=]+)=(.*)$/.exec(line);
    if (match) input[match[1]!] = match[2]!;
  }
  const env = validateEnvironment(input);
  process.env.DATABASE_URL = env.DATABASE_URL;
  const prisma = new PrismaService();
  try {
    console.log("Virtual trading eligibility:", {
      activeRealAccounts: await prisma.account.count({
        where: { mode: "REAL", status: "ACTIVE" },
      }),
      tradingEnabledUsers: await prisma.user.count({
        where: { tradingEnabled: true },
      }),
      enabledVirtualInstruments: await prisma.instrument.count({
        where: { demoEnabled: true },
      }),
      disabledVirtualInstruments: await prisma.instrument.count({
        where: { demoEnabled: false },
      }),
    });
    const deposits = await prisma.depositRequest.findMany({
      orderBy: { createdAt: "desc" },
      take: 5,
    });
    const evidence = new EvidenceService(prisma, new ConfigService(env));
    for (const [index, deposit] of deposits.entries()) {
      const image = deposit.evidenceObjectKey
        ? await prisma.evidenceFile.findUnique({
            where: { objectKey: deposit.evidenceObjectKey },
          })
        : null;
      console.log({
        index,
        status: deposit.status,
        screenshotLinked: Boolean(deposit.evidenceObjectKey),
        imageStatus: image?.status,
      });
      if (image) {
        try {
          console.log(
            `Screenshot read: ${(await evidence.read(image.id)).length} bytes`,
          );
        } catch {
          console.log("Screenshot read failed");
        }
      }
    }
    const session = await prisma.userSession.findFirst({
      where: { revokedAt: null, expiresAt: { gt: new Date() } },
      orderBy: { createdAt: "desc" },
    });
    if (!session) return;
    const recentEvents = await prisma.accountEvent.findMany({
      where: { userId: session.userId },
      orderBy: { sequence: "desc" },
      take: 3,
    });
    console.log(
      "Recent durable events:",
      recentEvents.map((e) => ({
        type: e.eventType,
        sequence: e.sequence.toString(),
      })),
    );
    const token = await new JwtService().signAsync(
      { sub: session.userId, sid: session.id, typ: "access" },
      {
        secret: env.JWT_ACCESS_SECRET,
        issuer: "primevest-api",
        audience: "primevest-mobile",
        expiresIn: 60,
      },
    );
    await new Promise<void>((resolve) => {
      const socket = io("http://127.0.0.1:3000/account", {
        transports: ["websocket"],
        auth: {
          token,
          afterSequence: recentEvents[0]
            ? (recentEvents[0].sequence - 1n).toString()
            : "0",
        },
        reconnection: false,
      });
      const timer = setTimeout(() => {
        console.log("Account socket readiness timed out");
        socket.disconnect();
        resolve();
      }, 15000);
      socket.on("account:error", (error) =>
        console.log("Account socket error:", error.code),
      );
      socket.on("account:recovery", (data) =>
        console.log(
          "Recovered funding statuses:",
          data.events.map(
            (event: { type: string; payload: { status?: string } }) => ({
              type: event.type,
              status: event.payload.status,
            }),
          ),
        ),
      );
      socket.on("connect_error", () =>
        console.log("Account socket connect failed"),
      );
      socket.on("account:ready", () => {
        console.log("Account socket ready");
        clearTimeout(timer);
        socket.disconnect();
        resolve();
      });
    });
  } finally {
    await prisma.$disconnect();
  }
}
main().catch(() => {
  console.error("Diagnosis failed");
  process.exitCode = 1;
});
