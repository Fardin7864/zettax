import { Injectable } from "@nestjs/common";
import { argon2id, hash, verify, type HashOptions } from "argon2";

const options: HashOptions = {
  type: argon2id,
  memoryCost: 65_536,
  timeCost: 3,
  parallelism: 1,
};

@Injectable()
export class PasswordHasherService {
  hash(value: string): Promise<string> {
    return hash(value, options);
  }

  async verify(hash: string, value: string): Promise<boolean> {
    try {
      return await verify(hash, value);
    } catch {
      return false;
    }
  }
}
