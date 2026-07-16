export interface HealthEvent {
  ok: boolean;
  latencyMs: number;
  errorCode: string | null;
  createdAt: string;
}

export interface Source {
  id: string;
  kind: 'archive' | 'podcast' | 'legado' | 'guowei';
  name: string;
  sourceUrl: string;
  enabled: boolean;
  priority: number;
  state: 'healthy' | 'degraded' | 'down' | 'unknown';
  testKeyword: string;
  consecutiveFailures: number;
  successCount: number;
  failureCount: number;
  lastLatencyMs: number | null;
  lastSuccessAt: string | null;
  lastFailureAt: string | null;
  lastErrorCode: string | null;
  createdAt: string;
  updatedAt: string;
  health: HealthEvent[];
}

export interface SourceCatalog {
  id: string;
  name: string;
  pageUrl: string;
  state: 'idle' | 'running' | 'healthy' | 'degraded';
  lastStartedAt: string | null;
  lastSuccessAt: string | null;
  lastErrorCode: string | null;
  lastTotal: number;
  lastAudio: number;
  lastRejected: number;
  lastImported: number;
  lastChanged: number;
  createdAt: string;
  updatedAt: string;
}

export interface SourceSyncSummary {
  trigger: 'startup' | 'scheduled' | 'manual';
  startedAt: string;
  completedAt: string;
  catalogs: Array<{
    id: string;
    name: string;
    ok: boolean;
    total: number;
    audio: number;
    rejected: number;
    imported: number;
    changed: number;
    enabled: number;
    errorCode: string | null;
    completedAt: string;
  }>;
}

export interface Summary {
  sourceCount: number;
  healthy: number;
  degraded: number;
  down: number;
  cachedBooks: number;
  cachedChapters: number;
  engineReady: boolean;
  sources: Source[];
}

export interface Book {
  id: string;
  sourceId: string;
  sourceName: string;
  title: string;
  author: string;
  narrator: string;
  cover: string;
  intro: string;
  category: string;
  chapterCount: number;
  totalDuration: number;
}

export interface Chapter {
  id: string;
  bookId: string;
  title: string;
  index: number;
  duration: number;
}

export interface AuditLog {
  id: number;
  action: string;
  target: string;
  detail: string;
  createdAt: string;
}
