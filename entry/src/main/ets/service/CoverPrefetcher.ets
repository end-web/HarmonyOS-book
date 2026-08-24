/**
 * CoverPrefetcher - 网络封面预下载
 *
 * 首页/搜索的封面由 Image(网络URL) 直接加载。冷启动首次访问图片 CDN
 * 需完整 DNS+TCP+TLS 握手，一次几十张并发很容易超时"转圈后不加载"。
 *
 * 方案:
 * 1. cacheDownload 预灌系统缓存，Image 命中缓存即可出图
 * 2. 有界并发队列，避免首屏 thrash
 * 3. 失败可重试：不因一次失败永久跳过
 * 4. 从 cover URL 解析 origin 预建链
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { cacheDownload } from '@kit.BasicServicesKit';
import { HttpClient } from './http/HttpClient';

const DOMAIN = 0x0000;
const TAG = 'CoverPrefetcher';

/** 防盗链头:不带 Referer/UA 时 file.* CDN 明显更慢甚至失败 */
const COVER_HEADERS: Record<string, string> = {
  'User-Agent':
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
  'Referer': 'https://www.tingyou.fm/'
};

/** 同时进行的预下载上限（冷启 TLS 握手重，过高会集体超时） */
const MAX_CONCURRENT: number = 4;
/** 单 URL 最大尝试次数（含首次） */
const MAX_ATTEMPTS: number = 5;
/** 无 success/error 回调时的兜底释放(ms) */
const IN_FLIGHT_WATCHDOG_MS: number = 50000;

export class CoverPrefetcher {
  private static initialized: boolean = false;
  private static pending: string[] = [];
  private static inFlight: Set<string> = new Set();
  private static succeeded: Set<string> = new Set();
  private static attemptCount: Map<string, number> = new Map();
  private static warmedOrigins: Set<string> = new Set();
  private static activeCount: number = 0;
  private static successHandlers: Map<string, () => void> = new Map();
  private static errorHandlers: Map<string, (err: cacheDownload.DownloadError) => void> = new Map();

  /** 应用启动时调用一次:文件缓存 + 内存缓存(默认内存为 0，Image 难命中)。 */
  static init(): void {
    if (CoverPrefetcher.initialized) {
      return;
    }
    try {
      cacheDownload.setFileCacheSize(100 * 1024 * 1024);
      cacheDownload.setMemoryCacheSize(32 * 1024 * 1024);
      CoverPrefetcher.initialized = true;
    } catch (_e) { /* ignore */ }
  }

  /**
   * 预下载单张封面。
   * @param highPriority true 时插到队首（首屏/可见卡片）
   */
  static prefetch(url: string, highPriority: boolean = false): void {
    if (!url || !url.startsWith('http')) {
      return;
    }
    if (CoverPrefetcher.succeeded.has(url)) {
      return;
    }
    if (CoverPrefetcher.inFlight.has(url)) {
      return;
    }
    const attempts: number = CoverPrefetcher.attemptCount.get(url) ?? 0;
    if (attempts >= MAX_ATTEMPTS) {
      return;
    }

    const pendingIdx: number = CoverPrefetcher.pending.indexOf(url);
    if (pendingIdx >= 0) {
      if (highPriority && pendingIdx > 0) {
        CoverPrefetcher.pending.splice(pendingIdx, 1);
        CoverPrefetcher.pending.unshift(url);
      }
      return;
    }

    if (highPriority) {
      CoverPrefetcher.pending.unshift(url);
    } else {
      CoverPrefetcher.pending.push(url);
    }
    CoverPrefetcher.prewarmOrigin(url);
    CoverPrefetcher.pump();
  }

  /** 批量预下载；前 priorityCount 张高优先级。 */
  static prefetchMany(urls: string[], priorityCount: number = 12): void {
    for (let i = 0; i < urls.length; i++) {
      CoverPrefetcher.prefetch(urls[i], i < priorityCount);
    }
  }

  /**
   * Image onError 时调用：清掉「永久失败」计数门槛内的状态并重新入队。
   * 允许用户停留首页时持续补齐未出图封面。
   */
  static retry(url: string): void {
    if (!url || !url.startsWith('http')) {
      return;
    }
    if (CoverPrefetcher.succeeded.has(url)) {
      return;
    }
    const attempts: number = CoverPrefetcher.attemptCount.get(url) ?? 0;
    if (attempts >= MAX_ATTEMPTS) {
      // 放宽一次：Image 侧主动重试说明仍需要，重置到 MAX-1 再试
      CoverPrefetcher.attemptCount.set(url, MAX_ATTEMPTS - 1);
    }
    if (CoverPrefetcher.inFlight.has(url)) {
      try {
        cacheDownload.cancel(url);
      } catch (_e) { /* ignore */ }
      CoverPrefetcher.releaseSlot(url);
    }
    const pendingIdx: number = CoverPrefetcher.pending.indexOf(url);
    if (pendingIdx >= 0) {
      CoverPrefetcher.pending.splice(pendingIdx, 1);
    }
    CoverPrefetcher.pending.unshift(url);
    CoverPrefetcher.prewarmOrigin(url);
    CoverPrefetcher.pump();
  }

  private static pump(): void {
    while (CoverPrefetcher.activeCount < MAX_CONCURRENT && CoverPrefetcher.pending.length > 0) {
      const url: string | undefined = CoverPrefetcher.pending.shift();
      if (url === undefined) {
        break;
      }
      if (CoverPrefetcher.succeeded.has(url) || CoverPrefetcher.inFlight.has(url)) {
        continue;
      }
      const attempts: number = CoverPrefetcher.attemptCount.get(url) ?? 0;
      if (attempts >= MAX_ATTEMPTS) {
        continue;
      }
      CoverPrefetcher.startOne(url);
    }
  }

  private static startOne(url: string): void {
    CoverPrefetcher.inFlight.add(url);
    CoverPrefetcher.activeCount++;
    const nextAttempt: number = (CoverPrefetcher.attemptCount.get(url) ?? 0) + 1;
    CoverPrefetcher.attemptCount.set(url, nextAttempt);

    const onSuccess = (): void => {
      CoverPrefetcher.detachHandlers(url);
      CoverPrefetcher.succeeded.add(url);
      CoverPrefetcher.releaseSlot(url);
      CoverPrefetcher.pump();
    };
    const onError = (_err: cacheDownload.DownloadError): void => {
      CoverPrefetcher.detachHandlers(url);
      CoverPrefetcher.releaseSlot(url);
      const attempts: number = CoverPrefetcher.attemptCount.get(url) ?? 0;
      if (attempts < MAX_ATTEMPTS) {
        const delayMs: number = Math.min(1000 * attempts, 5000);
        setTimeout((): void => {
          CoverPrefetcher.prefetch(url, false);
        }, delayMs);
      } else {
        hilog.warn(DOMAIN, TAG, 'give up after %{public}d attempts: %{public}s', attempts, url);
      }
      CoverPrefetcher.pump();
    };

    CoverPrefetcher.successHandlers.set(url, onSuccess);
    CoverPrefetcher.errorHandlers.set(url, onError);

    try {
      cacheDownload.onDownloadSuccess(url, onSuccess);
      cacheDownload.onDownloadError(url, onError);
      const retryOpts: cacheDownload.RetryOptions = { maxRetryCount: 2 };
      const timeoutOpts: cacheDownload.TimeoutOptions = {
        networkCheckTimeout: 15,
        httpTotalTimeout: 45
      };
      const options: cacheDownload.CacheDownloadOptions = {
        headers: COVER_HEADERS,
        cacheStrategy: cacheDownload.CacheStrategy.LAZY,
        retry: retryOpts,
        timeout: timeoutOpts
      };
      cacheDownload.download(url, options);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'download threw %{public}s: %{public}s', url, String(e));
      CoverPrefetcher.detachHandlers(url);
      CoverPrefetcher.releaseSlot(url);
      if (nextAttempt < MAX_ATTEMPTS) {
        setTimeout((): void => {
          CoverPrefetcher.prefetch(url, false);
        }, 1500);
      }
      CoverPrefetcher.pump();
      return;
    }

    // 部分 LAZY 命中/系统丢弃场景可能不回调，用看门狗释放槽位并允许再入队
    setTimeout((): void => {
      if (!CoverPrefetcher.inFlight.has(url)) {
        return;
      }
      if (CoverPrefetcher.succeeded.has(url)) {
        CoverPrefetcher.releaseSlot(url);
        CoverPrefetcher.pump();
        return;
      }
      hilog.warn(DOMAIN, TAG, 'watchdog release %{public}s', url);
      CoverPrefetcher.detachHandlers(url);
      try {
        cacheDownload.cancel(url);
      } catch (_e) { /* ignore */ }
      CoverPrefetcher.releaseSlot(url);
      const attempts: number = CoverPrefetcher.attemptCount.get(url) ?? 0;
      if (attempts < MAX_ATTEMPTS) {
        CoverPrefetcher.prefetch(url, false);
      }
      CoverPrefetcher.pump();
    }, IN_FLIGHT_WATCHDOG_MS);
  }

  private static releaseSlot(url: string): void {
    if (CoverPrefetcher.inFlight.has(url)) {
      CoverPrefetcher.inFlight.delete(url);
      CoverPrefetcher.activeCount = Math.max(0, CoverPrefetcher.activeCount - 1);
    }
  }

  private static detachHandlers(url: string): void {
    const successCb: (() => void) | undefined = CoverPrefetcher.successHandlers.get(url);
    const errorCb: ((err: cacheDownload.DownloadError) => void) | undefined =
      CoverPrefetcher.errorHandlers.get(url);
    try {
      if (successCb) {
        cacheDownload.offDownloadSuccess(url, successCb);
      } else {
        cacheDownload.offDownloadSuccess(url);
      }
    } catch (_e) { /* ignore */ }
    try {
      if (errorCb) {
        cacheDownload.offDownloadError(url, errorCb);
      } else {
        cacheDownload.offDownloadError(url);
      }
    } catch (_e) { /* ignore */ }
    CoverPrefetcher.successHandlers.delete(url);
    CoverPrefetcher.errorHandlers.delete(url);
  }

  private static prewarmOrigin(url: string): void {
    const origin: string = CoverPrefetcher.originOf(url);
    if (origin.length === 0) {
      return;
    }
    if (CoverPrefetcher.warmedOrigins.has(origin)) {
      return;
    }
    CoverPrefetcher.warmedOrigins.add(origin);
    HttpClient.preconnect(origin);
  }

  private static originOf(url: string): string {
    const m: RegExpExecArray | null = /^(https?:\/\/[^/]+)/.exec(url);
    if (m && m[1]) {
      return m[1];
    }
    return '';
  }
}
