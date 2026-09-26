import { IsIn, IsOptional, IsString, IsUUID, MaxLength } from "class-validator";

export class CreatePostDto {
  @IsOptional() @IsString() @MaxLength(2000) text?: string;
  @IsOptional() @IsUUID() imageEvidenceId?: string;
}

export class CreateCommentDto {
  @IsString() @MaxLength(1000) text!: string;
  @IsOptional() @IsUUID() parentId?: string;
}

export class ReactDto {
  @IsIn(["LIKE", "DISLIKE", "NONE"])
  value!: "LIKE" | "DISLIKE" | "NONE";
}
