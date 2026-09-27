import { afterEach, describe, expect, it, vi } from "vitest";
import sharp from "sharp";
import { GoogleProfileImporter } from "../src/auth/google-profile-importer.service";

afterEach(() => vi.unstubAllGlobals());

describe("verified Google profile import", () => {
  it("saves a missing name and private profile photo", async () => {
    const picture = await sharp({
      create: {
        width: 8,
        height: 8,
        channels: 3,
        background: "gold",
      },
    })
      .png()
      .toBuffer();
    const fetchImage = vi.fn(async () =>
      new Response(new Uint8Array(picture), {
        headers: { "content-type": "image/png" },
      }),
    );
    vi.stubGlobal("fetch", fetchImage);
    const prisma = {
      userProfile: {
        findUnique: vi.fn(async () => null),
        upsert: vi.fn(async () => ({ avatarObjectKey: null })),
        updateMany: vi.fn(async () => ({ count: 1 })),
      },
    };
    const evidence = {
      upload: vi.fn(async () => ({ objectKey: "profile/user-1/google.enc" })),
    };
    const importer = new GoogleProfileImporter(
      prisma as never,
      evidence as never,
    );

    await importer.importMissing("user-1", {
      name: " Jane  Trader ",
      picture: "https://lh3.googleusercontent.com/a/photo",
    });

    expect(prisma.userProfile.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { userId: "user-1" },
        create: expect.objectContaining({ fullName: "Jane Trader" }),
        update: {},
      }),
    );
    expect(evidence.upload).toHaveBeenCalledWith(
      "user-1",
      "USER",
      "PROFILE",
      expect.objectContaining({ mimetype: "image/png" }),
    );
    expect(prisma.userProfile.updateMany).toHaveBeenCalledWith({
      where: { userId: "user-1", avatarObjectKey: null },
      data: { avatarObjectKey: "profile/user-1/google.enc" },
    });
  });

  it("keeps a name and photo already chosen by the user", async () => {
    const fetchImage = vi.fn();
    vi.stubGlobal("fetch", fetchImage);
    const prisma = {
      userProfile: {
        findUnique: vi.fn(async () => ({ avatarObjectKey: "my-photo" })),
        upsert: vi.fn(),
        updateMany: vi.fn(),
      },
    };
    const importer = new GoogleProfileImporter(prisma as never, {} as never);

    await importer.importMissing("user-1", {
      name: "Another Google Name",
      picture: "https://lh3.googleusercontent.com/a/photo",
    });

    expect(prisma.userProfile.upsert).not.toHaveBeenCalled();
    expect(fetchImage).not.toHaveBeenCalled();
  });

  it("does not fetch an untrusted profile-image URL", async () => {
    const fetchImage = vi.fn();
    vi.stubGlobal("fetch", fetchImage);
    const prisma = {
      userProfile: {
        findUnique: vi.fn(async () => ({ avatarObjectKey: null })),
        updateMany: vi.fn(),
      },
    };
    const importer = new GoogleProfileImporter(prisma as never, {} as never);

    await importer.importMissing("user-1", {
      name: undefined,
      picture: "http://localhost/internal",
    });

    expect(fetchImage).not.toHaveBeenCalled();
    expect(prisma.userProfile.updateMany).not.toHaveBeenCalled();
  });
});
