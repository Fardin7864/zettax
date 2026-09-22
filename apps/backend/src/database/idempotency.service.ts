import { HttpStatus, Injectable } from "@nestjs/common";
import { ActorType, IdempotencyStatus, Prisma } from "@prisma/client";
import { createHash } from "node:crypto";
import { ApiErrorException } from "../http/api-error";

type ClaimInput = {
  actorType: ActorType;
  actorId: string;
  operation: string;
  key: string;
  request: unknown;
  expiresAt?: Date;
};

@Injectable()
export class IdempotencyService {
  hash(request: unknown): string {
    return createHash("sha256")
      .update(this.canonicalJson(request))
      .digest("hex");
  }

  async claim(tx: Prisma.TransactionClient, input: ClaimInput) {
    const requestHash = this.hash(input.request);
    const existing = await tx.idempotencyCommand.findUnique({
      where: {
        actorType_actorId_operation_key: {
          actorType: input.actorType,
          actorId: input.actorId,
          operation: input.operation,
          key: input.key,
        },
      },
    });
    if (existing) {
      if (existing.requestHash !== requestHash) {
        throw new ApiErrorException(
          "IDEMPOTENCY_KEY_REUSED",
          "The idempotency key was used for a different request.",
          HttpStatus.CONFLICT,
        );
      }
      if (
        existing.status === IdempotencyStatus.COMPLETED &&
        existing.response !== null
      ) {
        return { command: existing, replay: existing.response };
      }
      throw new ApiErrorException(
        "IDEMPOTENCY_COMMAND_IN_PROGRESS",
        "The original command is still being processed.",
        HttpStatus.CONFLICT,
      );
    }
    const command = await tx.idempotencyCommand.create({
      data: {
        actorType: input.actorType,
        actorId: input.actorId,
        operation: input.operation,
        key: input.key,
        requestHash,
        expiresAt: input.expiresAt ?? null,
      },
    });
    return { command, replay: null };
  }

  complete(
    tx: Prisma.TransactionClient,
    commandId: string,
    response: Prisma.InputJsonValue,
  ) {
    return tx.idempotencyCommand.update({
      where: { id: commandId },
      data: { status: IdempotencyStatus.COMPLETED, response },
    });
  }

  private canonicalJson(value: unknown): string {
    if (value === null || typeof value !== "object") {
      const encoded = JSON.stringify(value);
      return encoded === undefined ? "null" : encoded;
    }
    if (Array.isArray(value)) {
      return `[${value.map((item) => this.canonicalJson(item)).join(",")}]`;
    }
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${this.canonicalJson(record[key])}`)
      .join(",")}}`;
  }
}
