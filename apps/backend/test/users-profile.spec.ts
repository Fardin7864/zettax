import { describe, expect, it, vi } from "vitest";
import { UsersService } from "../src/users/users.service";
import { PrismaService } from "../src/database/prisma.service";
import { EvidenceService } from "../src/funding/evidence.service";

const body = { fullName: " Investor ", dateOfBirth: "2000-01-01", currentAddress: " Dhaka ", district: " Dhaka ", country: " Bangladesh " };
describe("profile editing", () => {
  it("updates only the authenticated user's profile and trims fields", async () => {
    const upsert = vi.fn().mockResolvedValue({});
    const prisma = { userProfile: { upsert }, user: { findUnique: vi.fn().mockResolvedValue({ id: "user-1" }) } };
    const service = new UsersService(prisma as unknown as PrismaService, {} as EvidenceService);
    await service.updateProfile("user-1", body);
    expect(upsert).toHaveBeenCalledWith(expect.objectContaining({ where: { userId: "user-1" }, update: expect.objectContaining({ fullName: "Investor", country: "Bangladesh" }) }));
  });
  it("rejects empty names and future birth dates before writing", async () => {
    const upsert = vi.fn();
    const service = new UsersService({ userProfile: { upsert } } as unknown as PrismaService, {} as EvidenceService);
    await expect(service.updateProfile("user-1", { ...body, fullName: " " })).rejects.toThrow();
    await expect(service.updateProfile("user-1", { ...body, dateOfBirth: "2999-01-01" })).rejects.toThrow();
    expect(upsert).not.toHaveBeenCalled();
  });
  it("reads only the authenticated owner's PROFILE picture", async () => {
    const findFirst = vi.fn().mockResolvedValue({ id: "avatar-1" });
    const read = vi.fn().mockResolvedValue(Buffer.from("picture"));
    const prisma = { userProfile: { findUnique: vi.fn().mockResolvedValue({ avatarObjectKey: "profile/user-1/pic.enc" }) }, evidenceFile: { findFirst } };
    const service = new UsersService(prisma as unknown as PrismaService, { read } as unknown as EvidenceService);
    expect(await service.avatar("user-1")).toEqual({ imageBase64: Buffer.from("picture").toString("base64") });
    expect(findFirst).toHaveBeenCalledWith({ where: { objectKey: "profile/user-1/pic.enc", ownerId: "user-1", ownerType: "USER", purpose: "PROFILE", status: "CLEAN" } });
  });
});
