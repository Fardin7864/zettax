import { PrismaClient } from "@prisma/client";
import * as argon2 from "argon2";
import { readFileSync } from "node:fs";

// Supply credentials through the local environment; never commit or print them.
const prisma = new PrismaClient();
async function main() {
  const input: unknown = process.argv.includes("--stdin")
    ? JSON.parse(readFileSync(0, "utf8"))
    : null;
  const record =
    input && typeof input === "object"
      ? (input as Record<string, unknown>)
      : {};
  const email = (
    typeof record.email === "string"
      ? record.email
      : process.env.PRIMEVEST_ADMIN_EMAIL
  )
    ?.trim()
    .toLowerCase();
  const password =
    typeof record.password === "string"
      ? record.password
      : process.env.PRIMEVEST_ADMIN_PASSWORD;
  const roleName =
    record.role === "funding-reviewer" ? "funding-reviewer" : "operations";
  if (
    record.role !== undefined &&
    !["operations", "funding-reviewer"].includes(String(record.role))
  )
    throw new Error("Unsupported bootstrap role");
  if (
    !email ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
    !password ||
    password.length < 16
  )
    throw new Error(
      "Set PRIMEVEST_ADMIN_EMAIL and PRIMEVEST_ADMIN_PASSWORD (at least 16 characters).",
    );
  await prisma.$transaction(async (tx) => {
    const existing = await tx.adminUser.findUnique({ where: { email } });
    if (existing)
      throw new Error(
        "Administrator already exists; bootstrap never resets credentials.",
      );
    const admin = await tx.adminUser.create({
      data: {
        email,
        passwordHash: await argon2.hash(password, { type: argon2.argon2id }),
      },
    });
    const role = await tx.role.upsert({
      where: { name: roleName },
      update: {},
      create: { name: roleName },
    });
    for (const key of roleName === "funding-reviewer"
      ? [
          "funding.overview",
          "deposit.read",
          "deposit.verify",
          "deposit.approve",
          "withdrawal.read",
          "withdrawal.approve",
          "withdrawal.mark_paid",
          "evidence.read",
          "evidence.write",
        ]
      : [
          "trading.configure",
          "funding.configure",
          "deposit.read",
          "deposit.approve",
          "withdrawal.read",
          "withdrawal.approve",
          "withdrawal.mark_paid",
          "operations.read",
          "evidence.read",
          "evidence.write",
          "deposit.verify",
          "kyc.configure",
          "treasury.read",
          "treasury.submit",
          "treasury.approve",
          "release.read",
          "audit.read",
          "admin.read",
          "changes.review",
          "users.configure",
          "admin.configure",
        ]) {
      const permission = await tx.permission.upsert({
        where: { key },
        update: {},
        create: { key, description: key },
      });
      await tx.rolePermission.upsert({
        where: {
          roleId_permissionId: { roleId: role.id, permissionId: permission.id },
        },
        update: {},
        create: { roleId: role.id, permissionId: permission.id },
      });
    }
    await tx.adminRoleAssignment.create({
      data: { adminUserId: admin.id, roleId: role.id },
    });
  }, { maxWait: 10_000, timeout: 30_000 });
  console.log("Administrator created.");
}
main()
  .catch((error: unknown) => {
    console.error(
      "Bootstrap failed:",
      error instanceof Error ? error.message : "Unknown error",
    );
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
