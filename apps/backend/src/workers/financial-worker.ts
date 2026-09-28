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
import { PredictionModule } from "../prediction/prediction.module";
import { PredictionService } from "../prediction/prediction.service";

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
    PredictionModule,
  ],
})
class FinancialWorkerModule {}

async function bootstrap(): Promise<void> {
  const app = await NestFactory.createApplicationContext(FinancialWorkerModule);
  const contracts = app.get(TimedContractsService);
  const predictions = app.get(PredictionService);
  const outbox = app.get(OutboxPublisherService);
  let stopping = false;
  const stop = () => {
    stopping = true;
  };
  process.once("SIGTERM", stop);
  process.once("SIGINT", stop);
  let nextQuestionCheck = 0;
  let questionGeneration: Promise<unknown> | undefined;
  while (!stopping) {
    try {
      await contracts.settleDueBatch(50);
      await predictions.settleDueBatch(5);
      if (!questionGeneration && Date.now() >= nextQuestionCheck) {
        nextQuestionCheck = Date.now() + 60_000;
        // Historical provider calls must never delay contract or prediction settlement.
        questionGeneration = predictions
          .ensurePlatformQuestions()
          .catch((error) => {
            console.error(
              "prediction generation failed",
              error instanceof Error ? error.name : "UnknownError",
            );
          })
          .finally(() => {
            questionGeneration = undefined;
          });
      }
      await outbox.publishBatch(100);
    } catch (error) {
      console.error(
        "financial worker cycle failed",
        error instanceof Error ? error.name : "UnknownError",
      );
    }
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  await questionGeneration;
  await app.close();
}

void bootstrap();
