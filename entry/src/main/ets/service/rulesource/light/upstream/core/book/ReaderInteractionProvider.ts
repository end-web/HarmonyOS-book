import { BookSource } from '../../model/data/Book';
import { BookSourceRuntimeSnapshotStore } from './BookSourceRuntimeSnapshot';

export class ReaderParagraphInteraction {
  order: number = -1;
  paragraphId: string = '';
  count: number = 0;
  target: string = 'paragraph';
}

export class ReaderInteractionBundle {
  providerId: string = '';
  bookId: string = '';
  chapterId: string = '';
  actions: ReaderParagraphInteraction[] = [];
}

export class ReaderInteractionPanel {
  html: string = '';
  baseUrl: string = '';
}

/**
 * Optional interaction providers must be registered by an independently reviewed, authorized
 * extension. The reader ships with no content-service provider, endpoint or credential.
 */
export interface ReaderInteractionProvider {
  id: string;
  matches(source: BookSource): boolean;
  fetch(source: BookSource, bookId: string, chapterId: string): Promise<ReaderInteractionBundle | null>;
  expandAction(source: BookSource, compactUrl: string): string;
  buildPanel(actionUrl: string): ReaderInteractionPanel | null;
}

class ReaderInteractionCacheEntry {
  bundle: ReaderInteractionBundle | null = null;
  expiresAt: number = 0;
}

export class ReaderInteractionProviderRegistry {
  private static providers: ReaderInteractionProvider[] = [];
  private static cache: Map<string, ReaderInteractionCacheEntry> = new Map();
  private static inFlight: Map<string, Promise<ReaderInteractionBundle | null>> = new Map();
  private static readonly CACHE_TTL_MS: number = 10 * 60 * 1000;
  private static readonly MAX_CACHE_ENTRIES: number = 64;

  static register(provider: ReaderInteractionProvider): void {
    if (!provider || !provider.id || this.providers.some((item: ReaderInteractionProvider): boolean =>
      item.id === provider.id)) return;
    this.providers.push(provider);
  }

  static resolve(source: BookSource): ReaderInteractionProvider | null {
    for (const provider of this.providers) {
      if (provider.matches(source)) return provider;
    }
    return null;
  }

  static expandAction(source: BookSource, compactUrl: string): string {
    const provider = this.resolve(source);
    return provider ? provider.expandAction(source, compactUrl) : compactUrl;
  }

  static buildPanel(actionUrl: string): ReaderInteractionPanel | null {
    for (const provider of this.providers) {
      const panel = provider.buildPanel(actionUrl);
      if (panel) return panel;
    }
    return null;
  }

  static async fetch(source: BookSource, bookId: string, chapterId: string): Promise<ReaderInteractionBundle | null> {
    const provider = this.resolve(source);
    if (!provider || !bookId || !chapterId) return null;
    const revision = BookSourceRuntimeSnapshotStore.get(source).signature;
    const key = `${provider.id}:${source.bookSourceUrl || source.bookSourceName}:${bookId}:${chapterId}:${revision}`;
    const cached = this.cache.get(key);
    if (cached && cached.expiresAt > Date.now()) return cached.bundle;
    const active = this.inFlight.get(key);
    if (active) return await active;

    const task = provider.fetch(source, bookId, chapterId);
    this.inFlight.set(key, task);
    try {
      const bundle = await task;
      const entry = new ReaderInteractionCacheEntry();
      entry.bundle = bundle;
      entry.expiresAt = Date.now() + this.CACHE_TTL_MS;
      this.cache.delete(key);
      this.cache.set(key, entry);
      while (this.cache.size > this.MAX_CACHE_ENTRIES) {
        const oldest = this.cache.keys().next().value as string | undefined;
        if (!oldest) break;
        this.cache.delete(oldest);
      }
      return bundle;
    } finally {
      this.inFlight.delete(key);
    }
  }
}
