import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import type { AppConfig } from '../config.js';
import type { AppDatabase } from '../database.js';
import type { CatalogService } from '../catalog-service.js';
import type { ReaderClient } from '../providers/reader-client.js';
import { clearSessionCookie, createSession, requireAdmin, setSessionCookie, verifyPassword, verifySession } from '../auth.js';
import { HttpError, sendData } from '../http.js';
import { parseSourceImport } from '../source-import.js';

export function createAdminRouter(
  config: AppConfig,
  db: AppDatabase,
  catalog: CatalogService,
  reader: ReaderClient
): Router {
  const router = Router();
  const secureCookie = config.PUBLIC_ORIGIN.startsWith('https://');
  const loginLimit = rateLimit({ windowMs: 15 * 60_000, limit: 8, standardHeaders: 'draft-7', legacyHeaders: false });

  router.post('/session', loginLimit, (request, response) => {
    const { password } = z.object({ password: z.string().min(8).max(200) }).parse(request.body);
    if (!verifyPassword(password, config.ADMIN_PASSWORD_HASH)) {
      db.audit('admin.login_failed', 'session', request.ip || 'unknown');
      throw new HttpError(401, 'INVALID_ADMIN_PASSWORD');
    }
    setSessionCookie(response, createSession(config.SESSION_SECRET), secureCookie);
    db.audit('admin.login', 'session', '登录成功');
    sendData(request, response, { authenticated: true });
  });

  router.get('/session', (request, response) => {
    const token = request.cookies?.jianhu_admin as string | undefined;
    sendData(request, response, { authenticated: verifySession(token, config.SESSION_SECRET) });
  });

  router.delete('/session', (request, response) => {
    clearSessionCookie(response, secureCookie);
    sendData(request, response, { authenticated: false });
  });

  router.use(requireAdmin(config.SESSION_SECRET));

  router.get('/summary', async (request, response) => {
    let engineReady = false;
    try { await reader.health(); engineReady = true; } catch { /* included below */ }
    const sources = db.listSources().map((source) => ({ ...source, config: undefined, health: db.healthHistory(source.id) }));
    sendData(request, response, { ...db.summary(), engineReady, sources });
  });

  router.get('/sources', (request, response) => {
    const sources = db.listSources().map((source) => ({ ...source, config: undefined, health: db.healthHistory(source.id) }));
    sendData(request, response, sources);
  });

  router.get('/sources/:id/export', (request, response) => {
    const source = db.getSource(request.params.id);
    if (!source) throw new HttpError(404, 'SOURCE_NOT_FOUND');
    sendData(request, response, source.config);
  });

  router.post('/sources/import', async (request, response) => {
    const parsed = await parseSourceImport(request.body);
    const imported = parsed.sources.map((source) => db.upsertLegadoSource(source, parsed.request.enabled, parsed.request.testKeyword));
    db.clearCache();
    db.audit('source.import', imported.map((item) => item.id).join(','), `导入 ${imported.length} 个音频源`);
    sendData(request, response, imported.map((source) => ({ ...source, config: undefined })), 'SOURCE_IMPORTED', 201);
  });

  router.patch('/sources/:id', (request, response) => {
    const input = z.object({
      enabled: z.boolean().optional(),
      name: z.string().trim().min(1).max(100).optional(),
      priority: z.number().int().min(1).max(1000).optional(),
      testKeyword: z.string().trim().max(100).optional()
    }).parse(request.body);
    const source = db.updateSource(request.params.id, input);
    if (!source) throw new HttpError(404, 'SOURCE_NOT_FOUND');
    db.clearCache();
    db.audit('source.update', source.id, JSON.stringify(input));
    sendData(request, response, { ...source, config: undefined }, 'SOURCE_UPDATED');
  });

  router.delete('/sources/:id', (request, response) => {
    if (!db.deleteSource(request.params.id)) throw new HttpError(400, 'SOURCE_DELETE_DENIED');
    db.clearCache();
    db.audit('source.delete', request.params.id, '删除书源');
    sendData(request, response, { deleted: true }, 'SOURCE_DELETED');
  });

  router.post('/sources/:id/test', async (request, response) => {
    const source = db.getSource(request.params.id);
    if (!source) throw new HttpError(404, 'SOURCE_NOT_FOUND');
    const input = z.object({ keyword: z.string().trim().max(100).optional() }).parse(request.body ?? {});
    const result = await catalog.testSource(source, input.keyword);
    db.audit('source.test', source.id, `${result.ok ? '成功' : '失败'} ${result.latencyMs}ms`);
    sendData(request, response, result, result.ok ? 'SOURCE_TEST_OK' : 'SOURCE_TEST_FAILED');
  });

  router.get('/debug/search', async (request, response) => {
    const query = z.object({ q: z.string().trim().min(1).max(100) }).parse(request.query);
    const result = await catalog.search(query.q, 1);
    sendData(request, response, result);
  });

  router.delete('/cache', (request, response) => {
    const deleted = db.clearCache();
    db.audit('cache.clear', 'cache', `清理 ${deleted} 条缓存`);
    sendData(request, response, { deleted }, 'CACHE_CLEARED');
  });

  router.get('/logs', (request, response) => {
    const limit = z.coerce.number().int().min(1).max(500).default(100).parse(request.query.limit ?? 100);
    sendData(request, response, db.listAuditLogs(limit));
  });

  return router;
}
