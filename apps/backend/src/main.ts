import { ValidationPipe } from "@nestjs/common";
import { NestFactory } from "@nestjs/core";
import { DocumentBuilder, SwaggerModule } from "@nestjs/swagger";
import helmet from "helmet";
import { AppModule } from "./app.module";

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule, { bufferLogs: true });
  app.use(helmet());
  app.enableCors({
    origin: (process.env.CORS_ORIGINS ?? "http://localhost:3001").split(","),
    credentials: true,
  });
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );
  app.setGlobalPrefix("api/v1", { exclude: ["health", "ready"] });

  const document = SwaggerModule.createDocument(
    app,
    new DocumentBuilder()
      .setTitle("Zettax API")
      .setDescription(
        "Zettax versioned API. Market display data is never an execution price.",
      )
      .setVersion("0.1.0")
      .addBearerAuth()
      .build(),
  );
  SwaggerModule.setup("api/docs", app, document);

  await app.listen(
    Number(process.env.BACKEND_PORT ?? 3000),
    process.env.BACKEND_HOST ?? "0.0.0.0",
  );
}

void bootstrap();
