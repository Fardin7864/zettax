import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { PrismaService } from '../src/database/prisma.service';
import { ContractPriceService } from '../src/timed-contracts/contract-price.service';
const suite=process.env.RUN_DATABASE_INTEGRATION==='true'?describe:describe.skip;
suite('durable contract observation archive',()=>{
  const prisma=new PrismaService();
  beforeAll(()=>prisma.$connect());
  afterAll(()=>prisma.$disconnect());
  afterEach(()=>vi.unstubAllGlobals());
  it('recovers the identical observation after restart without calling the provider',async()=>{
    const boundary=new Date(Date.now());
    const start=Math.floor(boundary.getTime()/1000)*1000-1000;
    const instrument={baseAsset:`TEST${Date.now()}`,assetClass:'CRYPTO'};
    const fetch=vi.fn().mockResolvedValue({ok:true,json:()=>Promise.resolve([[start,'1','1','1','100.12345678','1',start+999]])});
    vi.stubGlobal('fetch',fetch);
    const first=await new ContractPriceService(prisma).at(instrument,boundary);
    fetch.mockRejectedValue(new Error('offline'));
    const recovered=await new ContractPriceService(prisma).at(instrument,boundary);
    expect(recovered.price.toFixed()).toBe(first.price.toFixed());
    expect(fetch).toHaveBeenCalledTimes(1);
    await expect(prisma.contractPriceObservation.update({where:{source_timestamp:{source:first.providerId,timestamp:first.timestamp}},data:{price:'200'}})).rejects.toThrow();
    await expect(prisma.contractPriceObservation.delete({where:{source_timestamp:{source:first.providerId,timestamp:first.timestamp}}})).rejects.toThrow();
  });
});
