import {
  IsIn,
  IsISO8601,
  IsOptional,
  IsString,
  Matches,
} from "class-validator";

export class CreatePredictionQuestionDto {
  @IsString() @Matches(/^[a-z0-9-]{3,80}$/) instrumentId!: string;
  @IsIn(["ABOVE", "BELOW"]) condition!: "ABOVE" | "BELOW";
  @IsString() @Matches(/^(?:0|[1-9]\d*)(?:\.\d{1,12})?$/) targetPrice!: string;
  @IsISO8601() expiresAt!: string;
}

export class PlacePredictionDto {
  @IsIn(["DEMO", "REAL"]) accountMode!: "DEMO" | "REAL";
  @IsIn(["YES", "NO"]) side!: "YES" | "NO";
  @IsString() @Matches(/^(?:0|[1-9]\d*)(?:\.\d{1,2})?$/) stake!: string;
}

export class PredictionQuestionsQueryDto {
  @IsOptional() @IsIn(["OPEN", "SETTLED"]) status?: "OPEN" | "SETTLED";
  @IsOptional()
  @IsString()
  @Matches(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
  cursor?: string;
}
