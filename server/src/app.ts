import fs from 'node:fs';
import path from 'node:path';
import cookieParser from 'cookie-parser';
import express, { type Express } from 'express';
import helmet from 'helmet';
import pino from 'pino';
import { pinoHttp } from 'pino-http';
import type { AppConfig } from './config.js';
import { AppDatabase } from './database.js';
import { CatalogService } from './catalog-service.js';
import { errorHandler, notFound } from './http.js';
import { ReaderClient } from './providers/reader-client.js';
import { createAdminRouter } from './routes/admin-routes.js';
import { createPublicRouter } from './routes/public-routes.js';

export interface AppContext {
  app: Express;
  db: AppDatabase;
  catalog: CatalogService;
  reader: ReaderClient;
  close(): void;
}

export function createApp(config: AppConfig): AppContext {
  const app = express();
  const logger = pino({ level: config.LOG_LEVEL, redact: ['req.headers.cookie', 'req.body.password', 'req.body.content'] });
  const db = new AppDatabase(config.DB_PATH);
  const reader = new ReaderClient(config.READER_BASE_URL);
  const catalog = new CatalogService(db, config, reader);

  app.set('trust proxy', 1);
  app.disable('x-powered-by');
  app.use(pinoHttp({ logger, quietReqLogger: true }));
  app.use(helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        scriptSrc: ["'self'"],
        styleSrc: ["'self'", "'unsafe-inline'"],
        imgSrc: ["'self'", 'data:', 'https:'],
        connectSrc: ["'self'"],
        fontSrc: ["'self'", 'data:'],
        objectSrc: ["'none'"],
        frameAncestors: ["'none'"]
      }
    },
    crossOriginResourcePolicy: { policy: 'cross-origin' }
  }));
  app.use(express.json({ limit: '2mb', strict: true }));
  app.use(cookieParser());

  app.get('/', (_request, response) => response.redirect('/admin/'));
  app.use('/api/v1', createPublicRouter(catalog, reader));
  app.use('/api/admin', createAdminRouter(config, db, catalog, reader));

  const adminRoot = path.resolve(process.cwd(), 'public/admin');
  if (fs.existsSync(path.join(adminRoot, 'index.html'))) {
    app.use('/admin', express.static(adminRoot, { index: false, maxAge: config.NODE_ENV === 'production' ? '1h' : 0 }));
    app.get('/admin/{*path}', (_request, response) => response.sendFile(path.join(adminRoot, 'index.html')));
    app.get('/admin', (_request, response) => response.redirect('/admin/'));
  }

  app.use(notFound);
  app.use(errorHandler);
  catalog.startHealthChecks();

  return {
    app,
    db,
    catalog,
    reader,
    close: () => {
      catalog.stopHealthChecks();
      db.close();
    }
  };
}
