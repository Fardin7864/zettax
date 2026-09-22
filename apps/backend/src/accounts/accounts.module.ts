import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module";
import { AccountsController } from "./accounts.controller";
import { AccountsService } from "./accounts.service";
import { AccountEventsService } from "./account-events.service";
import { AccountRealtimeGateway } from "./account-realtime.gateway";

@Module({
  imports: [AuthModule],
  controllers: [AccountsController],
  providers: [AccountsService, AccountEventsService, AccountRealtimeGateway],
  exports: [AccountsService, AccountEventsService],
})
export class AccountsModule {}
