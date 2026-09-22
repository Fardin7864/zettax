// Local visual QA only. Refuses all databases except the isolated verification DB.
import { PrismaClient } from "@prisma/client";
import * as argon2 from "argon2";
import { createRequire } from "node:module";
async function preview() {
  if (
    new URL(process.env.DATABASE_URL ?? "").pathname !==
    "/primevest_contract_verify"
  )
    throw new Error("Preview requires isolated verification database");
  process.env.BACKEND_PORT = "3002";
  process.env.BACKEND_HOST = "127.0.0.1";
  process.env.COMPLIANCE_MODE = "DEMO_ONLY";
  process.env.CORS_ORIGINS = "http://localhost:3003";
  const db = new PrismaClient();
  const email = "visual-qa@example.invalid",
    password = "Local-visual-QA-only-2026";
  const role = await db.role.findUniqueOrThrow({
    where: { name: "operations" },
  });
  await db.adminUser.upsert({
    where: { email },
    create: {
      email,
      passwordHash: await argon2.hash(password),
      assignments: { create: { roleId: role.id } },
    },
    update: { active: true, passwordHash: await argon2.hash(password) },
  });
  await db.$disconnect();
  const requireRuntime = createRequire(`${process.cwd()}/package.json`);
  requireRuntime("./dist/apps/backend/src/main.js");
}
void preview();
