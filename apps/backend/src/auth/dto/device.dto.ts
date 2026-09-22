import { ApiPropertyOptional } from "@nestjs/swagger";
import { IsOptional, IsString, Length, MaxLength } from "class-validator";

export class DeviceDto {
  @ApiPropertyOptional({
    description: "Stable, app-generated device identifier",
  })
  @IsOptional()
  @IsString()
  @Length(16, 200)
  deviceFingerprint?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  deviceName?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(50)
  devicePlatform?: string;
}
