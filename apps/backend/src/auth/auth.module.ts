import { Module } from "@nestjs/common";
import { JwtModule } from "@nestjs/jwt";
import { AccessTokenGuard } from "./access-token.guard";
import { AuthController } from "./auth.controller";
import { AuthService } from "./auth.service";
import { PasswordHasherService } from "./password-hasher.service";
import { EvidenceModule } from "../funding/evidence.module";
import { GoogleProfileImporter } from "./google-profile-importer.service";

@Module({
  imports: [JwtModule.register({}), EvidenceModule],
  controllers: [AuthController],
  providers: [AuthService, GoogleProfileImporter, PasswordHasherService, AccessTokenGuard],
  exports: [AuthService, AccessTokenGuard],
})
export class AuthModule {}
