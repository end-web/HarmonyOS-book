import { SourceRuntimeStage } from './BookSourceRuntimeRouter';

export type SourceScriptNoticeHandler = (sourceName: string, message: string) => void;

/**
 * Surfaces java.toast()/longToast() raised while reading (book info, TOC, content), the way
 * Android Legado shows them. Search/explore/login screens already show their own notices, so
 * only the reading stages are forwarded. Preloading repeats the same script for many chapters;
 * an identical message from the same source is shown at most once per window.
 */
export class SourceScriptNotice {
  private static readonly REPEAT_WINDOW_MS: number = 15000;
  private static handler: SourceScriptNoticeHandler | null = null;
  private static lastKey: string = '';
  private static lastAt: number = 0;

  static setHandler(handler: SourceScriptNoticeHandler | null): void {
    SourceScriptNotice.handler = handler;
  }

  static emit(stage: string, sourceName: string, message: string): void {
    const text = (message || '').trim();
    if (!text || !SourceScriptNotice.handler || !SourceScriptNotice.isReadingStage(stage)) return;
    const key = `${sourceName}\n${text}`;
    const now = Date.now();
    if (key === SourceScriptNotice.lastKey && now - SourceScriptNotice.lastAt < SourceScriptNotice.REPEAT_WINDOW_MS) {
      return;
    }
    SourceScriptNotice.lastKey = key;
    SourceScriptNotice.lastAt = now;
    try {
      SourceScriptNotice.handler(sourceName, text);
    } catch (e) {
      console.warn('[SourceScriptNotice] handler failed:', e);
    }
  }

  private static isReadingStage(stage: string): boolean {
    return stage === SourceRuntimeStage.BOOK_INFO || stage === SourceRuntimeStage.TOC ||
      stage === SourceRuntimeStage.CONTENT;
  }
}
