import { describe, expect, it } from 'vitest';
import { createPasswordHash, createSession, verifyPassword, verifySession } from '../src/auth.js';

describe('admin auth', () => {
  it('verifies scrypt passwords without accepting a different password', () => {
    const hash = createPasswordHash('a-long-test-password', 'fixed-salt');
    expect(verifyPassword('a-long-test-password', hash)).toBe(true);
    expect(verifyPassword('wrong-password', hash)).toBe(false);
  });

  it('rejects expired or tampered sessions', () => {
    const secret = '12345678901234567890123456789012';
    const token = createSession(secret, 1_000);
    expect(verifySession(token, secret, 2_000)).toBe(true);
    expect(verifySession(token + 'x', secret, 2_000)).toBe(false);
    expect(verifySession(token, secret, 1_000 + 13 * 60 * 60 * 1000)).toBe(false);
  });
});
