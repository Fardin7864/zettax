import { ActorType, PrismaClient } from "@prisma/client";
import * as argon2 from "argon2";
import { randomBytes, randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";

type OperatorInput = {
  email: string;
  roles: string[];
};

const prisma = new PrismaClient();

function temporaryPassword(): string {
  return `${randomBytes(24).toString("base64url")}!9aA`;
}

async function main() {
  const input: unknown = JSON.parse(readFileSync(0, "utf8"));
  const records =
    input && typeof input === "object" && Array.isArray((input as { operators?: unknown }).operators)
      ? ((input as { operators: OperatorInput[] }).operators)
      : [];
  if (records.length !== 5) {
    throw new Error("Exactly five release operators are required.");
  }

  const emails = records.map((record) => record.email.trim().toLowerCase());
  if (
    new Set(emails).size !== records.length ||
    emails.some((email) => !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))
  ) {
    throw new Error("Release operator emails must be distinct and valid.");
  }

  const requiredRoles = new Set([
    "release-engineering",
    "release-security",
    "release-compliance",
    "release-legal",
    "release-custody",
    "release-payment_provider",
    "release-reconciliation",
    "release-operations",
    "release-treasury",
    "release-executive",
    "release-counterparty_risk",
  ]);
  const assignedReleaseRoles = new Set(
    records.flatMap((record) => record.roles.filter((role) => role.startsWith("release-"))),
  );
  if (
    requiredRoles.size !== assignedReleaseRoles.size ||
    [...requiredRoles].some((role) => !assignedReleaseRoles.has(role))
  ) {
    throw new Error("Every release authority must be assigned exactly through the operator plan.");
  }

  const credentials: Array<{ email: string; temporaryPassword: string }> = [];
  await prisma.$transaction(async (tx) => {
    const existing = await tx.adminUser.findMany({
      where: { email: { in: emails } },
      select: { email: true },
    });
    if (existing.length) {
      throw new Error(`Operator already exists: ${existing.map((row) => row.email).join(", ")}`);
    }

    const permissionSets: Record<string, string[]> = {
      "treasury-submitter": [
        "operations.read",
        "evidence.read",
        "evidence.write",
        "treasury.read",
        "treasury.submit",
      ],
      "treasury-reviewer": [
        "operations.read",
        "evidence.read",
        "treasury.read",
        "treasury.approve",
      ],
    };
    for (const [name, permissionKeys] of Object.entries(permissionSets)) {
      const role = await tx.role.upsert({
        where: { name },
        update: {},
        create: { name, description: `Independent ${name.replace("-", " ")}` },
      });
      const permissions = await tx.permission.findMany({
        where: { key: { in: permissionKeys } },
        select: { id: true, key: true },
      });
      if (permissions.length !== permissionKeys.length) {
        throw new Error(`Required permissions are missing for ${name}.`);
      }
      for (const permission of permissions) {
        await tx.rolePermission.upsert({
          where: {
            roleId_permissionId: {
              roleId: role.id,
              permissionId: permission.id,
            },
          },
          update: {},
          create: { roleId: role.id, permissionId: permission.id },
        });
      }
    }

    for (const record of records) {
      const email = record.email.trim().toLowerCase();
      const password = temporaryPassword();
      const roles = await tx.role.findMany({
        where: { name: { in: record.roles } },
        select: { id: true, name: true },
      });
      if (roles.length !== record.roles.length) {
        throw new Error(`One or more roles do not exist for ${email}.`);
      }
      const admin = await tx.adminUser.create({
        data: {
          email,
          passwordHash: await argon2.hash(password, { type: argon2.argon2id }),
        },
      });
      for (const role of roles) {
        await tx.adminRoleAssignment.create({
          data: { adminUserId: admin.id, roleId: role.id },
        });
      }
      await tx.auditLog.create({
        data: {
          actorType: ActorType.SYSTEM,
          action: "RELEASE_OPERATOR_PROVISIONED",
          resourceType: "AdminUser",
          resourceId: admin.id,
          newValue: { email, roles: roles.map((role) => role.name) },
          requestId: `local-release-operator-provision:${randomUUID()}`,
        },
      });
      credentials.push({ email, temporaryPassword: password });
    }
  }, { maxWait: 10_000, timeout: 60_000 });

  console.log(JSON.stringify({ credentials }, null, 2));
}

main()
  .catch((error: unknown) => {
    console.error(
      "Release operator provisioning failed:",
      error instanceof Error ? error.message : "Unknown error",
    );
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
