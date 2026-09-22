import { ApiProperty } from "@nestjs/swagger";
import { IsEmail, Length, Matches, MaxLength } from "class-validator";
import { DeviceDto } from "./device.dto";

export class RegisterDto extends DeviceDto {
  @ApiProperty()
  @IsEmail()
  @MaxLength(320)
  email!: string;

  @ApiProperty({ minLength: 12 })
  @Length(12, 128)
  @Matches(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z\d]).+$/, {
    message: "password must include upper, lower, number, and symbol",
  })
  password!: string;
}
