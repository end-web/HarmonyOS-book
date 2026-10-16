import { SourceCoverUrl } from './rulesource/light/upstream/core/nativesource/SourceCoverUrl';
import { LightSourceBridge } from './rulesource/light/LightSourceBridge';
import { LocalRuleSourceRepository } from './rulesource/LocalRuleSourceRepository';

/** Lazy source cover resolution, with bounded parallelism and request coalescing. */
export class SourceCoverService {
  private static inFlight: Map<string, Promise<string>> = new Map<string, Promise<string>>();
  private static active: number = 0;
  private static queue: (() => void)[] = [];

  static isEncoded(raw: string): boolean { return SourceCoverUrl.isEncoded(raw); }

  static async resolve(raw: string): Promise<string> {
    if (!SourceCoverUrl.isEncoded(raw)) return raw;
    const revision = LocalRuleSourceRepository.getLoginRevision();
    const key = `${revision}:${raw}`;
    const existing = SourceCoverService.inFlight.get(key);
    if (existing !== undefined) return existing;
    if (SourceCoverService.inFlight.size >= 64) throw new Error('Cover queue full');
    const pending = SourceCoverService.load(raw, revision);
    SourceCoverService.inFlight.set(key, pending);
    try { return await pending; } finally { SourceCoverService.inFlight.delete(key); }
  }

  private static async load(raw: string, revision: number): Promise<string> {
    if (SourceCoverService.active >= 3) {
      await new Promise<void>((resolve: () => void): void => { SourceCoverService.queue.push(resolve); });
    } else {
      SourceCoverService.active++;
    }
    try {
      const source = await LocalRuleSourceRepository.get(SourceCoverUrl.source(raw));
      if (source === undefined) throw new Error('Cover source no longer installed');
      const result = await LightSourceBridge.cover(source, raw, revision);
      if (revision !== LocalRuleSourceRepository.getLoginRevision()) throw new Error('Cover session changed');
      return result;
    } finally {
      const next = SourceCoverService.queue.shift();
      if (next !== undefined) next();
      else SourceCoverService.active--;
    }
  }
}
