import { HttpStatus, Injectable } from "@nestjs/common";
import {
  createCipheriv,
  createDecipheriv,
  createHmac,
  randomBytes,
  randomInt,
  timingSafeEqual,
} from "node:crypto";
import type { Prisma } from "@prisma/client";
import nodemailer from "nodemailer";
import { PrismaService } from "../database/prisma.service";
import { ApiErrorException } from "../http/api-error";

const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

export function encodeBase32(bytes: Buffer) {
  let bits = 0;
  let value = 0;
  let result = "";
  for (const byte of bytes) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) result += alphabet[(value >>> (bits -= 5)) & 31];
  }
  if (bits) result += alphabet[(value << (5 - bits)) & 31];
  return result;
}

function decodeBase32(value: string) {
  let bits = 0;
  let number = 0;
  const output: number[] = [];
  for (const character of value.toUpperCase()) {
    const index = alphabet.indexOf(character);
    if (index < 0) throw new Error("Invalid authenticator secret");
    number = (number << 5) | index;
    bits += 5;
    if (bits >= 8) output.push((number >>> (bits -= 8)) & 255);
  }
  return Buffer.from(output);
}

export function totp(secret: string, counter: number) {
  const message = Buffer.alloc(8);
  message.writeBigUInt64BE(BigInt(counter));
  const digest = createHmac("sha1", decodeBase32(secret))
    .update(message)
    .digest();
  const offset = digest[digest.length - 1]! & 15;
  return ((digest.readUInt32BE(offset) & 0x7fffffff) % 1_000_000)
    .toString()
    .padStart(6, "0");
}

function invalidCode(): never {
  throw new ApiErrorException(
    "VERIFICATION_FAILED",
    "The verification code is invalid or expired.",
    HttpStatus.FORBIDDEN,
  );
}

@Injectable()
export class VerificationService {
  constructor(private readonly prisma: PrismaService) {}

  private key() {
    const value = process.env.MFA_ENCRYPTION_KEY || "";
    if (!/^[0-9a-f]{64}$/i.test(value)) {
      throw new ApiErrorException(
        "VERIFICATION_UNAVAILABLE",
        "Withdrawal verification is not configured yet.",
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
    return Buffer.from(value, "hex");
  }

  private encrypt(secret: string) {
    const iv = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", this.key(), iv);
    const ciphertext = Buffer.concat([
      cipher.update(secret, "utf8"),
      cipher.final(),
    ]);
    return [iv, cipher.getAuthTag(), ciphertext]
      .map((item) => item.toString("base64url"))
      .join(".");
  }

  private decrypt(value: string) {
    const [iv, tag, ciphertext] = value
      .split(".")
      .map((item) => Buffer.from(item, "base64url"));
    const decipher = createDecipheriv("aes-256-gcm", this.key(), iv!);
    decipher.setAuthTag(tag!);
    return Buffer.concat([
      decipher.update(ciphertext!),
      decipher.final(),
    ]).toString("utf8");
  }

  private codeHash(userId: string, code: string) {
    return createHmac("sha256", this.key())
      .update(`${userId}:${code}`)
      .digest("hex");
  }

  async status(userId: string) {
    const [user, security] = await Promise.all([
      this.prisma.user.findUnique({
        where: { id: userId },
        select: { email: true },
      }),
      this.prisma.userSecurity.findUnique({
        where: { userId },
        select: { totpEnabled: true },
      }),
    ]);
    return {
      authenticatorEnabled: security?.totpEnabled === true,
      email: user?.email ?? null,
      emailAvailable: Boolean(
        process.env.SMTP_HOST &&
        process.env.SMTP_USER &&
        process.env.SMTP_PASSWORD &&
        /^[0-9a-f]{64}$/i.test(process.env.MFA_ENCRYPTION_KEY || ""),
      ),
    };
  }

  async beginAuthenticator(userId: string) {
    const security = await this.prisma.userSecurity.findUnique({
      where: { userId },
    });
    if (security?.totpEnabled) {
      throw new ApiErrorException(
        "ALREADY_ENABLED",
        "Authenticator verification is already enabled.",
        HttpStatus.CONFLICT,
      );
    }
    const secret = encodeBase32(randomBytes(20));
    const encrypted = this.encrypt(secret);
    await this.prisma.userSecurity.upsert({
      where: { userId },
      create: { userId, pendingTotpSecret: encrypted },
      update: { pendingTotpSecret: encrypted },
    });
    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      select: { email: true },
    });
    return {
      secret,
      otpAuthUrl: `otpauth://totp/${encodeURIComponent(`Zettax:${user.email}`)}?secret=${secret}&issuer=Zettax&algorithm=SHA1&digits=6&period=30`,
    };
  }

  async confirmAuthenticator(userId: string, code: string) {
    const security = await this.prisma.userSecurity.findUnique({
      where: { userId },
    });
    if (!security?.pendingTotpSecret || security.totpEnabled) invalidCode();
    const secret = this.decrypt(security.pendingTotpSecret);
    const counter = Math.floor(Date.now() / 30_000);
    const accepted = [counter - 1, counter, counter + 1].find(
      (item) => totp(secret, item) === code,
    );
    if (accepted === undefined) invalidCode();
    await this.prisma.userSecurity.update({
      where: { userId },
      data: {
        encryptedTotpSecret: security.pendingTotpSecret,
        pendingTotpSecret: null,
        totpEnabled: true,
        lastTotpCounter: BigInt(accepted),
      },
    });
    return { authenticatorEnabled: true };
  }

  async sendEmailCode(userId: string) {
    const host = process.env.SMTP_HOST;
    const username = process.env.SMTP_USER;
    const password = process.env.SMTP_PASSWORD;
    const from = process.env.SMTP_FROM || "noreply@zettax.com";
    if (!host || !username || !password) {
      throw new ApiErrorException(
        "EMAIL_UNAVAILABLE",
        "Email verification is not configured yet.",
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      select: { email: true },
    });
    const prior = await this.prisma.userSecurity.findUnique({
      where: { userId },
      select: { emailCodeSentAt: true },
    });
    if (
      prior?.emailCodeSentAt &&
      Date.now() - prior.emailCodeSentAt.getTime() < 60_000
    ) {
      throw new ApiErrorException(
        "CODE_RATE_LIMITED",
        "Wait one minute before requesting another code.",
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
    const code = randomInt(0, 1_000_000).toString().padStart(6, "0");
    const codeHash = this.codeHash(userId, code);
    const expires = new Date(Date.now() + 5 * 60_000);
    await this.prisma.userSecurity.upsert({
      where: { userId },
      create: {
        userId,
        emailCodeHash: codeHash,
        emailCodeExpiresAt: expires,
        emailCodeSentAt: new Date(),
        emailCodeAttempts: 0,
      },
      update: {
        emailCodeHash: codeHash,
        emailCodeExpiresAt: expires,
        emailCodeSentAt: new Date(),
        emailCodeAttempts: 0,
      },
    });
    const port = Number(process.env.SMTP_PORT || 465);
    const transport = nodemailer.createTransport({
      host,
      port,
      secure: port === 465,
      auth: { user: username, pass: password },
    });
    try {
      await transport.sendMail({
        from,
        to: user.email,
        subject: "Zettax withdrawal verification code",
        text: `Your Zettax withdrawal verification code is ${code}. It expires in 5 minutes. If you did not request a withdrawal, ignore this email.`,
      });
    } catch {
      await this.prisma.userSecurity.update({
        where: { userId },
        data: {
          emailCodeHash: null,
          emailCodeExpiresAt: null,
          emailCodeSentAt: null,
        },
      });
      throw new ApiErrorException(
        "EMAIL_DELIVERY_FAILED",
        "The verification email could not be sent. Try again later.",
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
    return { sent: true, expiresInSeconds: 300 };
  }

  async verifyWithdrawal(
    tx: Prisma.TransactionClient,
    userId: string,
    method: "AUTHENTICATOR" | "EMAIL",
    code: string,
  ) {
    const security = await tx.userSecurity.findUnique({ where: { userId } });
    if (!security) invalidCode();
    if (method === "AUTHENTICATOR") {
      if (!security.totpEnabled || !security.encryptedTotpSecret) invalidCode();
      const counter = Math.floor(Date.now() / 30_000);
      const secret = this.decrypt(security.encryptedTotpSecret);
      const accepted = [counter - 1, counter, counter + 1].find(
        (item) =>
          item > Number(security.lastTotpCounter ?? -1n) &&
          totp(secret, item) === code,
      );
      if (accepted === undefined) invalidCode();
      const updated = await tx.userSecurity.updateMany({
        where: {
          userId,
          OR: [
            { lastTotpCounter: null },
            { lastTotpCounter: { lt: BigInt(accepted) } },
          ],
        },
        data: { lastTotpCounter: BigInt(accepted) },
      });
      if (updated.count !== 1) invalidCode();
    } else {
      if (
        !security.emailCodeHash ||
        !security.emailCodeExpiresAt ||
        security.emailCodeExpiresAt.getTime() < Date.now() ||
        security.emailCodeAttempts >= 5
      )
        invalidCode();
      const actual = Buffer.from(this.codeHash(userId, code), "hex");
      const expected = Buffer.from(security.emailCodeHash, "hex");
      if (
        actual.length !== expected.length ||
        !timingSafeEqual(actual, expected)
      ) {
        await this.prisma.userSecurity.update({
          where: { userId },
          data: { emailCodeAttempts: { increment: 1 } },
        });
        invalidCode();
      }
      const updated = await tx.userSecurity.updateMany({
        where: { userId, emailCodeHash: security.emailCodeHash },
        data: {
          emailCodeHash: null,
          emailCodeExpiresAt: null,
          emailCodeAttempts: 0,
        },
      });
      if (updated.count !== 1) invalidCode();
    }
  }
}
