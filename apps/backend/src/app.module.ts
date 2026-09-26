import {
  MiddlewareConsumer,
  Module,
  NestModule,
  RequestMethod,
} from "@nestjs/common";
import { ConfigModule } from "@nestjs/config";
import { APP_FILTER, APP_GUARD, APP_INTERCEPTOR } from "@nestjs/core";
import { ThrottlerGuard, ThrottlerModule } from "@nestjs/throttler";
import { AuthModule } from "./auth/auth.module";
import { AdminModule } from "./admin/admin.module";
import { SecurityModule } from "./admin/security.module";
import { OperationsModule } from "./operations/operations.module";
import { ChangesModule } from "./operations/changes.module";
import { ComplianceModule } from "./compliance/compliance.module";
import { HealthModule } from "./health/health.module";
import { MarketsModule } from "./markets/markets.module";
import { validateEnvironment } from "./config/environment";
import { ApiEnvelopeInterceptor } from "./http/api-envelope.interceptor";
import { RequestIdMiddleware } from "./http/request-id.middleware";
import { ApiExceptionFilter } from "./http/api-exception.filter";
import { TradingModule } from "./trading/trading.module";
import { DatabaseModule } from "./database/database.module";
import { FundingModule } from "./funding/funding.module";
import { AccountsModule } from "./accounts/accounts.module";
import { UsersModule } from "./users/users.module";
import { TimedContractsModule } from "./timed-contracts/timed-contracts.module";
import { SiteEventsController } from "./site-events/site-events.controller";
import { VerificationModule } from "./verification/verification.module";
import { CommunityModule } from "./community/community.module";
import { PredictionModule } from "./prediction/prediction.module";

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      cache: true,
      validate: validateEnvironment,
    }),
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: 100 }]),
    DatabaseModule,
    AuthModule,
    VerificationModule,
    CommunityModule,
    PredictionModule,
    AdminModule,
    SecurityModule,
    OperationsModule,
    ChangesModule,
    ComplianceModule,
    HealthModule,
    MarketsModule,
    FundingModule,
    TradingModule,
    UsersModule,
    AccountsModule,
    TimedContractsModule,
  ],
  providers: [
    { provide: APP_INTERCEPTOR, useClass: ApiEnvelopeInterceptor },
    { provide: APP_FILTER, useClass: ApiExceptionFilter },
    { provide: APP_GUARD, useClass: ThrottlerGuard },
  ],
  controllers: [SiteEventsController],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer): void {
    consumer
      .apply(RequestIdMiddleware)
      .forRoutes({ path: "{*path}", method: RequestMethod.ALL });
  }
}
