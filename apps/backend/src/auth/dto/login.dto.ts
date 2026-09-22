import { ApiProperty } from "@nestjs/swagger";
import { IsString, Length, MaxLength } from "class-validator";
import { DeviceDto } from "./device.dto";

export class LoginDto extends DeviceDto {
  @ApiProperty({ description: "Email address or +880 mobile number" })
  @IsString()
  @MaxLength(320)
  identifier!: string;

  @ApiProperty()
  @IsString()
  @Length(1, 128)
  password!: string;
}
