import { Module } from "@nestjs/common";
import { ConfigModule } from "@nestjs/config";
import { NestFactory } from "@nestjs/core";
import { ComplianceModule } from "../compliance/compliance.module";
import { validateEnvironment } from "../config/environment";
import { DatabaseModule } from "../database/database.module";
import { OutboxPublisherService } from "../database/outbox-publisher.service";
import { TimedContractsModule } from "../timed-contracts/timed-contracts.module";
import { TimedContractsService } from "../timed-contracts/timed-contracts.service";
import { TradingModule } from "../trading/trading.module";

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      cache: true,
      validate: validateEnvironment,
    }),
    DatabaseModule,
    ComplianceModule,
    TradingModule,
    TimedContractsModule,
  ],
})
class FinancialWorkerModule {}

async function bootstrap(): Promise<void> {
  const app = await NestFactory.createApplicationContext(FinancialWorkerModule);
  const contracts = app.get(TimedContractsService);
  const outbox = app.get(OutboxPublisherService);
  let stopping = false;
  const stop = () => {
    stopping = true;
  };
  process.once("SIGTERM", stop);
  process.once("SIGINT", stop);
  while (!stopping) {
    try {
      await contracts.settleDueBatch(50);
      await outbox.publishBatch(100);
    } catch (error) {
      console.error(
        "financial worker cycle failed",
        error instanceof Error ? error.name : "UnknownError",
      );
    }
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  await app.close();
}

void bootstrap();
