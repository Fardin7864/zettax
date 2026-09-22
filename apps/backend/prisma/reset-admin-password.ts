import { ActorType, PrismaClient } from "@prisma/client";
import * as argon2 from "argon2";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";

// Credentials are accepted only over stdin so they are not stored in source,
// environment files, or command arguments.
const prisma = new PrismaClient();

async function main() {
  const input: unknown = JSON.parse(readFileSync(0, "utf8"));
  const record =
    input && typeof input === "object"
      ? (input as Record<string, unknown>)
      : {};
  const email =
    typeof record.email === "string" ? record.email.trim().toLowerCase() : "";
  const password = typeof record.password === "string" ? record.password : "";

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new Error("A valid administrator email is required.");
  }
  if (password.length < 16) {
    throw new Error(
      "The administrator password must contain at least 16 characters.",
    );
  }

  const passwordHash = await argon2.hash(password, {
    type: argon2.argon2id,
  });
  await prisma.$transaction(async (tx) => {
    const admin = await tx.adminUser.findUnique({
      where: { email },
      select: { id: true, active: true },
    });
    if (!admin?.active) {
      throw new Error("An active administrator with that email was not found.");
    }
    await tx.adminUser.update({
      where: { id: admin.id },
      data: { passwordHash },
    });
    await tx.auditLog.create({
      data: {
        actorType: ActorType.SYSTEM,
        action: "ADMIN_PASSWORD_RESET_LOCAL",
        resourceType: "AdminUser",
        resourceId: admin.id,
        newValue: { passwordChanged: true },
        requestId: `local-admin-password-reset:${randomUUID()}`,
      },
    });
  });

  console.log("Administrator password reset completed.");
}

main()
  .catch((error: unknown) => {
    console.error(
      "Administrator password reset failed:",
      error instanceof Error ? error.message : "Unknown error",
    );
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
