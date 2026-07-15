import type { NextFunction, Request, Response } from 'express';
import type { ApiEnvelope } from './types.js';
import { requestId } from './utils.js';

export class HttpError extends Error {
  constructor(public readonly status: number, public readonly code: string, message = code) {
    super(message);
  }
}

function currentRequestId(request: Request): string {
  const value = (request as Request & { id?: unknown }).id;
  return typeof value === 'string' || typeof value === 'number' ? String(value) : requestId();
}

export function sendData<T>(request: Request, response: Response, data: T, code = 'OK', status = 200): void {
  const payload: ApiEnvelope<T> = { code, data, requestId: currentRequestId(request), serverTime: Date.now() };
  response.status(status).json(payload);
}

export function notFound(_request: Request, response: Response): void {
  response.status(404).json({ code: 'NOT_FOUND', data: null, requestId: requestId(), serverTime: Date.now() });
}

export function errorHandler(error: unknown, request: Request, response: Response, _next: NextFunction): void {
  if (response.headersSent) return;
  if (error instanceof HttpError) {
    sendData(request, response, null, error.code, error.status);
    return;
  }
  const message = error instanceof Error ? error.message : 'INTERNAL_ERROR';
  if (message.includes('NOT_FOUND')) {
    sendData(request, response, null, message, 404);
    return;
  }
  if (message.includes('ONLY_AUDIO') || message.includes('INVALID_SOURCE') || message.includes('NO_SOURCE') ||
    message.includes('TOO_MANY') || message.includes('IMPORT_') || message.includes('PRIVATE_NETWORK')) {
    sendData(request, response, null, message.replace(/^.*?:/, ''), 400);
    return;
  }
  request.log?.error({ err: error }, 'request failed');
  sendData(request, response, null, 'INTERNAL_ERROR', 500);
}
