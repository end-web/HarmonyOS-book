/**
 * BigInt - 简化大数运算库（用于 RSA 加密）
 *
 * 以 2^26 为基底（避免 JS 中 32 位乘法溢出），支持：
 * - 从 hex 字符串构造
 * - 加减乘除模
 * - 模幂运算（square-and-multiply）
 * - 转换为 hex 字符串
 */

interface DivModResult {
  q: BigInteger;
  r: BigInteger;
}

const BASE = 0x4000000; // 2^26
const BASE_LOG = 26;

export class BigInteger {
  // 小端序存储：limbs[0] 是最低位
  limbs: number[] = [];
  sign: number = 1; // 1 正，-1 负

  constructor(value?: number | string | number[]) {
    if (value === undefined) {
      this.limbs = [0];
    } else if (typeof value === 'number') {
      this.fromNumber(value);
    } else if (typeof value === 'string') {
      this.fromHex(value);
    } else if (Array.isArray(value)) {
      this.limbs = value.slice();
      this.sign = 1;
    }
    this.normalize();
  }

  private fromNumber(n: number): void {
    if (n < 0) { this.sign = -1; n = -n; }
    this.limbs = [];
    while (n > 0) {
      this.limbs.push(n % BASE);
      n = Math.floor(n / BASE);
    }
    if (this.limbs.length === 0) this.limbs = [0];
  }

  fromHex(hex: string): void {
    this.sign = 1;
    const clean = hex.replace(/^0x/i, '').replace(/^0+/, '') || '0';
    this.limbs = [];
    let i = clean.length;
    while (i > 0) {
      const start = Math.max(0, i - BASE_LOG / 4);
      const chunk = clean.substring(start, i);
      this.limbs.push(parseInt(chunk, 16));
      i = start;
    }
    this.normalize();
  }

  toHex(): string {
    if (this.isZero()) return '0';
    let hex = '';
    for (let i = this.limbs.length - 1; i >= 0; i--) {
      const chunk = this.limbs[i].toString(16);
      if (hex === '') {
        hex = chunk;
      } else {
        hex += chunk.padStart(BASE_LOG / 4, '0');
      }
    }
    return (this.sign < 0 ? '-' : '') + hex;
  }

  isZero(): boolean {
    return this.limbs.length === 1 && this.limbs[0] === 0;
  }

  private normalize(): void {
    while (this.limbs.length > 1 && this.limbs[this.limbs.length - 1] === 0) {
      this.limbs.pop();
    }
    if (this.limbs.length === 0) this.limbs = [0];
    if (this.isZero()) this.sign = 1;
  }

  clone(): BigInteger {
    const r = new BigInteger();
    r.limbs = this.limbs.slice();
    r.sign = this.sign;
    return r;
  }

  abs(): BigInteger {
    const r = this.clone();
    r.sign = 1;
    return r;
  }

  negate(): BigInteger {
    const r = this.clone();
    if (!r.isZero()) r.sign = -r.sign;
    return r;
  }

  compare(other: BigInteger): number {
    if (this.sign !== other.sign) return this.sign - other.sign;
    const cmp = this.compareAbs(other);
    return this.sign < 0 ? -cmp : cmp;
  }

  private compareAbs(other: BigInteger): number {
    if (this.limbs.length !== other.limbs.length) {
      return this.limbs.length - other.limbs.length;
    }
    for (let i = this.limbs.length - 1; i >= 0; i--) {
      if (this.limbs[i] !== other.limbs[i]) {
        return this.limbs[i] - other.limbs[i];
      }
    }
    return 0;
  }

  add(other: BigInteger): BigInteger {
    if (this.sign === other.sign) {
      return this.addAbs(other);
    }
    const cmp = this.compareAbs(other);
    if (cmp === 0) return new BigInteger(0);
    if (cmp > 0) {
      return this.subAbs(other);
    } else {
      const r = other.subAbs(this);
      r.sign = this.sign;
      return r;
    }
  }

  subtract(other: BigInteger): BigInteger {
    return this.add(other.negate());
  }

  private addAbs(other: BigInteger): BigInteger {
    const maxLen = Math.max(this.limbs.length, other.limbs.length);
    const result: number[] = [];
    let carry = 0;
    for (let i = 0; i < maxLen || carry; i++) {
      const a = i < this.limbs.length ? this.limbs[i] : 0;
      const b = i < other.limbs.length ? other.limbs[i] : 0;
      const sum = a + b + carry;
      result.push(sum % BASE);
      carry = Math.floor(sum / BASE);
    }
    const r = new BigInteger();
    r.limbs = result;
    r.sign = this.sign;
    r.normalize();
    return r;
  }

  private subAbs(other: BigInteger): BigInteger {
    // Assumes this >= other in absolute value
    const result: number[] = [];
    let borrow = 0;
    for (let i = 0; i < this.limbs.length; i++) {
      const a = this.limbs[i];
      const b = i < other.limbs.length ? other.limbs[i] : 0;
      let diff = a - b - borrow;
      if (diff < 0) {
        diff += BASE;
        borrow = 1;
      } else {
        borrow = 0;
      }
      result.push(diff);
    }
    const r = new BigInteger();
    r.limbs = result;
    r.sign = this.sign;
    r.normalize();
    return r;
  }

  multiply(other: BigInteger): BigInteger {
    const result: number[] = new Array(this.limbs.length + other.limbs.length).fill(0);
    for (let i = 0; i < this.limbs.length; i++) {
      let carry = 0;
      for (let j = 0; j < other.limbs.length || carry; j++) {
        const b = j < other.limbs.length ? other.limbs[j] : 0;
        const prod = result[i + j] + this.limbs[i] * b + carry;
        result[i + j] = prod % BASE;
        carry = Math.floor(prod / BASE);
      }
    }
    const r = new BigInteger();
    r.limbs = result;
    r.sign = this.sign * other.sign;
    r.normalize();
    return r;
  }

  divide(divisor: BigInteger): BigInteger {
    const dm = this.divMod(divisor);
    return dm.q;
  }

  mod(divisor: BigInteger): BigInteger {
    const dm = this.divMod(divisor);
    return dm.r;
  }

  private divMod(divisor: BigInteger): DivModResult {
    if (divisor.isZero()) throw new Error('Division by zero');

    const cmp = this.compareAbs(divisor);
    if (cmp < 0) {
      const r: DivModResult = { q: new BigInteger(0), r: this.abs() };
      return r;
    }
    if (cmp === 0) {
      const r: DivModResult = { q: new BigInteger(this.sign * divisor.sign), r: new BigInteger(0) };
      return r;
    }

    // 简化的长除法
    const dividend = this.abs();
    const div = divisor.abs();
    const result: number[] = new Array(dividend.limbs.length).fill(0);

    let remainder = new BigInteger(0);
    for (let i = dividend.limbs.length - 1; i >= 0; i--) {
      // 将 remainder 左移一位（乘 BASE）并加上当前 limb
      remainder.limbs.unshift(dividend.limbs[i]);
      remainder.normalize();

      // 二分搜索商的当前位
      let lo = 0, hi = BASE - 1;
      while (lo < hi) {
        const mid = Math.floor((lo + hi + 1) / 2);
        const test = div.multiply(new BigInteger(mid));
        if (test.compareAbs(remainder) <= 0) {
          lo = mid;
        } else {
          hi = mid - 1;
        }
      }
      result[i] = lo;
      if (lo > 0) {
        remainder = remainder.subAbs(div.multiply(new BigInteger(lo)));
      }
    }

    const q = new BigInteger();
    q.limbs = result;
    q.sign = this.sign * divisor.sign;
    q.normalize();

    remainder.sign = this.sign;
    remainder.normalize();

    const dm: DivModResult = { q: q, r: remainder };
    return dm;
  }

  /**
   * 模幂运算：this^exp mod mod
   * 使用 square-and-multiply 算法
   */
  modPow(exp: BigInteger, mod: BigInteger): BigInteger {
    if (mod.isZero()) throw new Error('Modulus is zero');
    if (mod.compare(new BigInteger(1)) === 0) return new BigInteger(0);

    let result = new BigInteger(1);
    let base = this.mod(mod);

    // 从最低位到最高位处理指数的每个 bit
    for (let i = 0; i < exp.limbs.length; i++) {
      let word = exp.limbs[i];
      for (let bit = 0; bit < BASE_LOG; bit++) {
        if (word & 1) {
          result = result.multiply(base).mod(mod);
        }
        base = base.multiply(base).mod(mod);
        word >>= 1;
      }
    }

    return result;
  }
}
