import { ApiProperty } from "@nestjs/swagger";
import { IsJWT, IsOptional, IsString, MaxLength } from "class-validator";
import { DeviceDto } from "./device.dto";

export class GoogleAuthDto extends DeviceDto {
  @ApiProperty({ description: "Google OpenID Connect ID token" })
  @IsJWT()
  idToken!: string;

  @IsOptional() @IsString() @MaxLength(100) displayName?: string;
  @IsOptional() @IsString() @MaxLength(2048) photoUrl?: string;
}
