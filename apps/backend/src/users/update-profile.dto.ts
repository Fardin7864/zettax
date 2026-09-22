import { IsDateString, IsIn, IsOptional, IsString, MaxLength, MinLength } from "class-validator";

export class UpdateProfileDto {
  @IsString() @MinLength(1) @MaxLength(100) fullName!: string;
  @IsDateString() dateOfBirth!: string;
  @IsOptional() @IsIn(["Male", "Female", "Other", "Prefer not to say"]) gender?: string;
  @IsString() @MaxLength(500) currentAddress!: string;
  @IsString() @MaxLength(100) district!: string;
  @IsString() @MinLength(1) @MaxLength(100) country!: string;
}
