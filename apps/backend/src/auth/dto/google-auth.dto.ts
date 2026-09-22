import { ApiProperty } from "@nestjs/swagger";
import { IsJWT } from "class-validator";
import { DeviceDto } from "./device.dto";

export class GoogleAuthDto extends DeviceDto {
  @ApiProperty({ description: "Google OpenID Connect ID token" })
  @IsJWT()
  idToken!: string;
}
