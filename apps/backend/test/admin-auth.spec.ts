import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { describe,expect,it } from 'vitest';
import { AdminSession } from '../src/admin/admin.module';
describe('separate administrator identity',()=>{
  const secret='test-only-very-long-secret-not-for-production';
  const jwt=new JwtService();
  const session=new AdminSession(new ConfigService({JWT_ACCESS_SECRET:secret}),jwt);
  it('accepts admin sessions and rejects customer sessions',async()=>{
    expect((await session.verify(await session.sign('admin-test'))).sub).toBe('admin-test');
    const customer=await jwt.signAsync({sub:'customer'}, {secret,audience:'primevest-mobile',issuer:'primevest-api'});
    await expect(session.verify(customer)).rejects.toThrow();
  });
  it('does not accept admin tokens as customer tokens',async()=>{
    const token=await session.sign('admin-test');
    await expect(jwt.verifyAsync(token,{secret,audience:'primevest-mobile',issuer:'primevest-api'})).rejects.toThrow();
  });
});
