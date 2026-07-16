import { z } from 'zod';

const booleanEnv = z.enum(['true', 'false']).default('true').transform((value) => value === 'true');

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  HOST: z.string().default('0.0.0.0'),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  DB_PATH: z.string().default('./data/jianhu.db'),
  READER_BASE_URL: z.string().url().default('http://127.0.0.1:4396'),
  ADMIN_PASSWORD_HASH: z.string().min(20),
  SESSION_SECRET: z.string().min(32),
  PUBLIC_ORIGIN: z.string().url().default('http://localhost:3000'),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent']).default('info'),
  SOURCE_CONCURRENCY: z.coerce.number().int().min(1).max(8).default(4),
  SOURCE_TIMEOUT_MS: z.coerce.number().int().min(1000).max(60000).default(12000),
  SEARCH_CACHE_TTL_SECONDS: z.coerce.number().int().min(30).max(86400).default(600),
  DETAIL_CACHE_TTL_SECONDS: z.coerce.number().int().min(60).max(604800).default(21600),
  CHAPTER_CACHE_TTL_SECONDS: z.coerce.number().int().min(60).max(604800).default(3600),
  SOURCE_SYNC_ENABLED: booleanEnv,
  SOURCE_SYNC_HOUR_CST: z.coerce.number().int().min(0).max(23).default(4),
  SOURCE_SYNC_MINUTE_CST: z.coerce.number().int().min(0).max(59).default(20),
  SOURCE_SYNC_TEST_LIMIT: z.coerce.number().int().min(0).max(100).default(10),
  SOURCE_SYNC_MAX_ENABLED: z.coerce.number().int().min(1).max(50).default(16),
  SOURCE_SYNC_TEST_KEYWORD: z.string().trim().min(1).max(100).default('三国演义'),
  SOURCE_SYNC_FETCH_TIMEOUT_MS: z.coerce.number().int().min(5000).max(300000).default(120000),
  SOURCE_CATALOG_YIOVE_IMPORT_URL: z.string().url()
    .default('https://shuyuan-api.yiove.com/import/book-sources/1-100'),
  GUOWEI_API_BASE_URL: z.string().url().default('https://yssapi.guoweitech.com/'),
  GUOWEI_SIGNING_KEY: z.string().default('')
});

export type AppConfig = z.infer<typeof envSchema>;

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  return envSchema.parse(env);
}
