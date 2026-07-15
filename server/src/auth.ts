import { createHmac, randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';
import type { NextFunction, Request, Response } from 'express';

const COOKIE_NAME = 'jianhu_admin';

export function createPasswordHash(password: string, salt = randomBytes(16).toString('base64url')): string {
  const digest = scryptSync(password, salt, 64).toString('base64url');
  return `scrypt$${salt}$${digest}`;
}

export function verifyPassword(password: string, encoded: string): boolean {
  const [algorithm, salt, expected] = encoded.split('$');
  if (algorithm !== 'scrypt' || !salt || !expected) return false;
  const actual = scryptSync(password, salt, 64);
  const expectedBuffer = Buffer.from(expected, 'base64url');
  return actual.length === expectedBuffer.length && timingSafeEqual(actual, expectedBuffer);
}

function signature(value: string, secret: string): string {
  return createHmac('sha256', secret).update(value).digest('base64url');
}

export function createSession(secret: string, now = Date.now()): string {
  const payload = Buffer.from(JSON.stringify({ role: 'admin', exp: now + 12 * 60 * 60 * 1000 })).toString('base64url');
  return `${payload}.${signature(payload, secret)}`;
}

export function verifySession(token: string | undefined, secret: string, now = Date.now()): boolean {
  if (!token) return false;
  const [payload, provided] = token.split('.');
  if (!payload || !provided) return false;
  const expected = Buffer.from(signature(payload, secret));
  const actual = Buffer.from(provided);
  if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) return false;
  try {
    const decoded = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as { role?: string; exp?: number };
    return decoded.role === 'admin' && typeof decoded.exp === 'number' && decoded.exp > now;
  } catch {
    return false;
  }
}

export function setSessionCookie(response: Response, token: string, secure: boolean): void {
  response.cookie(COOKIE_NAME, token, {
    httpOnly: true,
    secure,
    sameSite: 'strict',
    path: '/',
    maxAge: 12 * 60 * 60 * 1000
  });
}

export function clearSessionCookie(response: Response, secure: boolean): void {
  response.clearCookie(COOKIE_NAME, { httpOnly: true, secure, sameSite: 'strict', path: '/' });
}

export function requireAdmin(secret: string) {
  return (request: Request, response: Response, next: NextFunction): void => {
    if (!verifySession(request.cookies?.[COOKIE_NAME] as string | undefined, secret)) {
      response.status(401).json({ code: 'ADMIN_AUTH_REQUIRED', data: null });
      return;
    }
    next();
  };
}
