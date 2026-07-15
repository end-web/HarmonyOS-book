import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import type { CatalogService } from '../catalog-service.js';
import type { ReaderClient } from '../providers/reader-client.js';
import { HttpError, sendData } from '../http.js';

export function createPublicRouter(catalog: CatalogService, reader: ReaderClient): Router {
  const router = Router();
  const searchLimit = rateLimit({ windowMs: 60_000, limit: 60, standardHeaders: 'draft-7', legacyHeaders: false });
  const resolveLimit = rateLimit({ windowMs: 60_000, limit: 120, standardHeaders: 'draft-7', legacyHeaders: false });

  router.get('/health', async (request, response) => {
    let engine: Record<string, unknown> | null = null;
    let engineReady = false;
    try {
      engine = await reader.health();
      engineReady = true;
    } catch { /* health response reports the failure */ }
    sendData(request, response, { status: engineReady ? 'ready' : 'degraded', engineReady, engine });
  });

  router.get('/sources', (request, response) => {
    sendData(request, response, { name: '简·欢聚合', capabilities: ['search', 'detail', 'chapters', 'audio'] });
  });

  router.get('/audio-books/search', searchLimit, async (request, response) => {
    const query = z.object({
      q: z.string().trim().min(1).max(100),
      page: z.coerce.number().int().min(1).max(100).default(1)
    }).parse(request.query);
    const result = await catalog.search(query.q, query.page);
    sendData(request, response, result);
  });

  router.get('/audio-books/:id', async (request, response) => {
    const id = z.string().min(8).max(100).parse(request.params.id);
    const book = await catalog.getBook(id);
    sendData(request, response, book);
  });

  router.get('/audio-books/:id/chapters', async (request, response) => {
    const id = z.string().min(8).max(100).parse(request.params.id);
    const refresh = request.query.refresh === '1';
    const chapters = await catalog.getChapters(id, refresh);
    sendData(request, response, chapters);
  });

  router.post('/audio-chapters/:id/resolve', resolveLimit, async (request, response) => {
    const id = z.string().min(8).max(100).parse(request.params.id);
    const resolution = await catalog.resolve(id);
    if (!resolution.url) throw new HttpError(502, 'AUDIO_RESOLVE_FAILED');
    sendData(request, response, resolution);
  });

  return router;
}
