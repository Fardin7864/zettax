import { ConfigService } from "@nestjs/config";
import { describe, expect, it, vi } from "vitest";
import { EvidenceService } from "../src/funding/evidence.service";
import { PrismaService } from "../src/database/prisma.service";

describe("deposit screenshot retention", () => {
  it("removes expired objects before marking their metadata deleted", async () => {
    const findMany = vi
      .fn()
      .mockResolvedValue([{ id: "image", objectKey: "deposit/image.enc" }]);
    const update = vi.fn().mockResolvedValue({});
    const removeObject = vi.fn().mockResolvedValue(undefined);
    const service = new EvidenceService(
      { evidenceFile: { findMany, update } } as unknown as PrismaService,
      new ConfigService(),
    );
    vi.spyOn(
      service as unknown as { storage: () => unknown },
      "storage",
    ).mockReturnValue({ removeObject });
    await service.deleteExpiredDeposits();
    expect(findMany.mock.calls[0]?.[0].where.purpose).toBe("DEPOSIT");
    expect(removeObject).toHaveBeenCalledWith(
      "primevest-evidence",
      "deposit/image.enc",
    );
    expect(update).toHaveBeenCalledWith({
      where: { id: "image" },
      data: { status: "DELETED" },
    });
    expect(removeObject.mock.invocationCallOrder[0]).toBeLessThan(
      update.mock.invocationCallOrder[0]!,
    );
  });

  it("keeps metadata retryable if storage deletion fails", async () => {
    const update = vi.fn();
    const service = new EvidenceService(
      {
        evidenceFile: {
          findMany: vi
            .fn()
            .mockResolvedValue([
              { id: "image", objectKey: "deposit/image.enc" },
            ]),
          update,
        },
      } as unknown as PrismaService,
      new ConfigService(),
    );
    vi.spyOn(
      service as unknown as { storage: () => unknown },
      "storage",
    ).mockReturnValue({
      removeObject: vi.fn().mockRejectedValue(new Error("offline")),
    });
    await service.deleteExpiredDeposits();
    expect(update).not.toHaveBeenCalled();
  });
});
