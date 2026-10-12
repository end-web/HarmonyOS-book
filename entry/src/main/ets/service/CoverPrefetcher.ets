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
import { PlatformCompat } from '../utils/PlatformCompat';
import { http } from '@kit.NetworkKit';

const DOMAIN = 0x0000;
const TAG = 'CoverPrefetcher';

/** 通用图片请求只携带 UA，避免把某个书源的 Referer 泄漏给其他图片站点。 */
const COVER_HEADERS: Record<string, string> = {
  'User-Agent':
    'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
};

/** 同时进行的预下载上限（冷启 TLS 握手重，过高会集体超时） */
const MAX_CONCURRENT: number = 4;
/** 单 URL 最大尝试次数（含首次） */
const MAX_ATTEMPTS: number = 5;
/** 无 success/error 回调时的兜底释放(ms) */
const IN_FLIGHT_WATCHDOG_MS: number = 50000;
const MAX_PENDING: number = 128;
const MAX_HISTORY: number = 512;
const MAX_ORIGINS: number = 64;

export class CoverPrefetcher {
  /** 超分读取原始图片，沿用书源图片请求头，不使用列表解码后的缩略图。 */
  static async loadOriginal(url: string): Promise<ArrayBuffer> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        header: CoverPrefetcher.requestHeaders.get(url) ?? COVER_HEADERS,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 10000, readTimeout: 15000, maxLimit: 4 * 1024 * 1024
      });
      if (response.responseCode !== 200 || !(response.result instanceof ArrayBuffer) ||
        response.result.byteLength === 0 || response.result.byteLength > 4 * 1024 * 1024) {
        throw new Error('Invalid cover image');
      }
      return response.result;
    } finally {
      request.destroy();
    }
  }
  private static initialized: boolean = false;
  private static pending: string[] = [];
  private static inFlight: Set<string> = new Set();
  private static succeeded: Set<string> = new Set();
  private static attemptCount: Map<string, number> = new Map();
  private static warmedOrigins: Set<string> = new Set();
  private static requestHeaders: Map<string, Record<string, string>> =
    new Map<string, Record<string, string>>();
  private static activeCount: number = 0;
  private static successHandlers: Map<string, () => void> = new Map();
  private static errorHandlers: Map<string, (err: cacheDownload.DownloadError) => void> = new Map();
  private static watchdogs: Map<string, number> = new Map<string, number>();
  private static polls: Map<string, number> = new Map<string, number>();
  private static retries: Map<string, number> = new Map<string, number>();

  /** 应用启动时调用一次:文件缓存 + 内存缓存(默认内存为 0，Image 难命中)。 */
  static init(): void {
    if (CoverPrefetcher.initialized) {
      return;
    }
    try {
      cacheDownload.setFileCacheSize(100 * 1024 * 1024);
      cacheDownload.setMemoryCacheSize(32 * 1024 * 1024);
      if (!PlatformCompat.supports(23)) {
        cacheDownload.setDownloadInfoListSize(256);
      }
      CoverPrefetcher.initialized = true;
    } catch (_e) { /* ignore */ }
  }

  /** 注册规则源解析出的图片请求头；同 URL 后注册的详情上下文优先。 */
  static registerHeaders(url: string, headers: Record<string, string>): void {
    if (!url.startsWith('http')) return;
    const copied: Record<string, string> = {};
    const names = Object.keys(headers);
    for (const name of names) {
      const lower = name.toLowerCase();
      if (lower === 'host' || lower === 'content-length' || lower === 'accept-encoding') continue;
      copied[name] = headers[name] ?? '';
    }
    if (!CoverPrefetcher.hasHeader(copied, 'user-agent')) {
      copied['User-Agent'] = COVER_HEADERS['User-Agent'] ?? '';
    }
    CoverPrefetcher.requestHeaders.delete(url);
    CoverPrefetcher.requestHeaders.set(url, copied);
    for (const key of CoverPrefetcher.requestHeaders.keys()) {
      if (CoverPrefetcher.requestHeaders.size <= MAX_HISTORY) break;
      if (!CoverPrefetcher.isPending(key)) CoverPrefetcher.requestHeaders.delete(key);
    }
  }

  /**
   * 预下载单张封面。
   * @param highPriority true 时插到队首（首屏/可见卡片）
   */
  static prefetch(url: string, highPriority: boolean = false): void {
    if (!url || !url.startsWith('http')) {
      return;
    }
    CoverPrefetcher.clearTimer(CoverPrefetcher.retries, url);
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
      if (CoverPrefetcher.pending.length > MAX_PENDING) CoverPrefetcher.pending.pop();
    } else {
      if (CoverPrefetcher.pending.length >= MAX_PENDING) return;
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
    CoverPrefetcher.clearTimer(CoverPrefetcher.retries, url);
    if (CoverPrefetcher.succeeded.has(url)) {
      return;
    }
    const attempts: number = CoverPrefetcher.attemptCount.get(url) ?? 0;
    if (attempts >= MAX_ATTEMPTS) {
      // 放宽一次：Image 侧主动重试说明仍需要，重置到 MAX-1 再试
      CoverPrefetcher.attemptCount.set(url, MAX_ATTEMPTS - 1);
    }
    if (CoverPrefetcher.inFlight.has(url)) {
      // 先解绑并使旧回调失效，再取消；cancel 也可能同步/延迟回调 error。
      CoverPrefetcher.detachHandlers(url);
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
    if (CoverPrefetcher.pending.length > MAX_PENDING) CoverPrefetcher.pending.pop();
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
    CoverPrefetcher.attemptCount.delete(url);
    CoverPrefetcher.attemptCount.set(url, nextAttempt);
    CoverPrefetcher.trimHistory();

    const onSuccess = (): void => {
      if (CoverPrefetcher.successHandlers.get(url) !== onSuccess) return;
      CoverPrefetcher.detachHandlers(url);
      CoverPrefetcher.succeeded.add(url);
      CoverPrefetcher.releaseSlot(url);
      CoverPrefetcher.pump();
    };
    const onError = (): void => {
      if (CoverPrefetcher.successHandlers.get(url) !== onSuccess) return;
      CoverPrefetcher.detachHandlers(url);
      CoverPrefetcher.releaseSlot(url);
      const attempts: number = CoverPrefetcher.attemptCount.get(url) ?? 0;
      if (attempts < MAX_ATTEMPTS) {
        const delayMs: number = Math.min(1000 * attempts, 5000);
        CoverPrefetcher.scheduleRetry(url, delayMs);
      } else {
        hilog.warn(DOMAIN, TAG, 'give up after %{public}d attempts: %{public}s', attempts, url);
      }
      CoverPrefetcher.pump();
    };

    CoverPrefetcher.successHandlers.set(url, onSuccess);
    CoverPrefetcher.errorHandlers.set(url, onError);

    try {
      const options: cacheDownload.CacheDownloadOptions = {
        headers: CoverPrefetcher.requestHeaders.get(url) ?? COVER_HEADERS
      };
      if (PlatformCompat.supports(23)) {
        cacheDownload.onDownloadSuccess(url, onSuccess);
        cacheDownload.onDownloadError(url, onError);
        options.cacheStrategy = cacheDownload.CacheStrategy.LAZY;
      }
      if (PlatformCompat.supports(26)) {
        options.retry = { maxRetryCount: 2 };
        options.timeout = { networkCheckTimeout: 15, httpTotalTimeout: 45 };
      }
      // API 20 的查询可能仍保留上次结果，不能把旧失败当成这次下载已经完成。
      let previousInfo: string = '';
      if (!PlatformCompat.supports(23)) {
        const info: cacheDownload.DownloadInfo | undefined = cacheDownload.getDownloadInfo(url);
        if (info !== undefined) previousInfo = JSON.stringify(info);
      }
      cacheDownload.download(url, options);
      if (!PlatformCompat.supports(23)) {
        CoverPrefetcher.pollDownloadInfo(url, previousInfo, onSuccess, onError);
      }
    } catch (e) {
      if (CoverPrefetcher.successHandlers.get(url) !== onSuccess) return;
      hilog.warn(DOMAIN, TAG, 'download threw %{public}s: %{public}s', url, String(e));
      CoverPrefetcher.detachHandlers(url);
      CoverPrefetcher.releaseSlot(url);
      if (nextAttempt < MAX_ATTEMPTS) {
        CoverPrefetcher.scheduleRetry(url, 1500);
      }
      CoverPrefetcher.pump();
      return;
    }

    // 部分 LAZY 命中/系统丢弃场景可能不回调，用看门狗释放槽位并允许再入队
    // 缓存命中可能在 download 内完成，完成后不得再挂一个空等 50 秒的闭包。
    if (CoverPrefetcher.successHandlers.get(url) !== onSuccess) return;
    const watchdog = setTimeout((): void => {
      if (CoverPrefetcher.successHandlers.get(url) !== onSuccess) return;
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
    CoverPrefetcher.watchdogs.set(url, watchdog);
  }

  private static releaseSlot(url: string): void {
    CoverPrefetcher.clearTimer(CoverPrefetcher.watchdogs, url);
    CoverPrefetcher.clearTimer(CoverPrefetcher.polls, url);
    if (CoverPrefetcher.inFlight.has(url)) {
      CoverPrefetcher.inFlight.delete(url);
      CoverPrefetcher.activeCount = Math.max(0, CoverPrefetcher.activeCount - 1);
    }
  }

  /** API 20 没有完成事件，读取下载结果；仍由统一看门狗取消超时任务并释放并发槽位。 */
  private static pollDownloadInfo(url: string, previousInfo: string,
    onSuccess: () => void, onError: () => void): void {
    if (CoverPrefetcher.successHandlers.get(url) !== onSuccess) return;
    const timer = setTimeout((): void => {
      if (CoverPrefetcher.successHandlers.get(url) !== onSuccess) return;
      CoverPrefetcher.polls.delete(url);
      try {
        const info: cacheDownload.DownloadInfo | undefined = cacheDownload.getDownloadInfo(url);
        if (info !== undefined && JSON.stringify(info) !== previousInfo) {
          if (info.resource.size > 0) {
            onSuccess();
            return;
          }
          if (info.resource.size < 0) {
            onError();
            return;
          }
        }
      } catch (_e) {
        // 系统暂未提供结果时继续等待，最长等待时间由看门狗限制。
      }
      CoverPrefetcher.pollDownloadInfo(url, previousInfo, onSuccess, onError);
    }, 250);
    CoverPrefetcher.polls.set(url, timer);
  }

  private static detachHandlers(url: string): void {
    if (!PlatformCompat.supports(23)) {
      CoverPrefetcher.successHandlers.delete(url);
      CoverPrefetcher.errorHandlers.delete(url);
      return;
    }
    const successCb: (() => void) | undefined = CoverPrefetcher.successHandlers.get(url);
    const errorCb: ((err: cacheDownload.DownloadError) => void) | undefined =
      CoverPrefetcher.errorHandlers.get(url);
    // 先移除身份标记，已进入事件队列的旧回调也会被守卫拦住。
    CoverPrefetcher.successHandlers.delete(url);
    CoverPrefetcher.errorHandlers.delete(url);
    try {
      if (successCb) {
        cacheDownload.offDownloadSuccess(url, successCb);
      }
    } catch (_e) { /* ignore */ }
    try {
      if (errorCb) {
        cacheDownload.offDownloadError(url, errorCb);
      }
    } catch (_e) { /* ignore */ }
  }

  private static clearTimer(timers: Map<string, number>, url: string): void {
    const timer = timers.get(url);
    if (timer !== undefined) clearTimeout(timer);
    timers.delete(url);
  }

  private static scheduleRetry(url: string, delayMs: number): void {
    CoverPrefetcher.clearTimer(CoverPrefetcher.retries, url);
    if (CoverPrefetcher.retries.size >= MAX_PENDING) {
      const oldest = CoverPrefetcher.retries.keys().next();
      if (!oldest.done) CoverPrefetcher.clearTimer(CoverPrefetcher.retries, oldest.value);
    }
    const timer = setTimeout((): void => {
      if (CoverPrefetcher.retries.get(url) !== timer) return;
      CoverPrefetcher.retries.delete(url);
      CoverPrefetcher.prefetch(url, false);
    }, delayMs);
    CoverPrefetcher.retries.set(url, timer);
  }

  private static isPending(url: string): boolean {
    return CoverPrefetcher.inFlight.has(url) || CoverPrefetcher.retries.has(url) ||
      CoverPrefetcher.pending.indexOf(url) >= 0;
  }

  private static trimHistory(): void {
    for (const url of CoverPrefetcher.attemptCount.keys()) {
      if (CoverPrefetcher.attemptCount.size <= MAX_HISTORY) break;
      if (CoverPrefetcher.isPending(url)) continue;
      CoverPrefetcher.attemptCount.delete(url);
      CoverPrefetcher.succeeded.delete(url);
    }
  }

  private static prewarmOrigin(url: string): void {
    const origin: string = CoverPrefetcher.originOf(url);
    if (origin.length === 0) {
      return;
    }
    if (CoverPrefetcher.warmedOrigins.has(origin)) {
      CoverPrefetcher.warmedOrigins.delete(origin);
      CoverPrefetcher.warmedOrigins.add(origin);
      return;
    }
    CoverPrefetcher.warmedOrigins.add(origin);
    if (CoverPrefetcher.warmedOrigins.size > MAX_ORIGINS) {
      const oldest = CoverPrefetcher.warmedOrigins.values().next();
      if (!oldest.done) CoverPrefetcher.warmedOrigins.delete(oldest.value);
    }
    HttpClient.preconnect(origin);
  }

  private static originOf(url: string): string {
    const m: RegExpExecArray | null = /^(https?:\/\/[^/]+)/.exec(url);
    if (m && m[1]) {
      return m[1];
    }
    return '';
  }

  private static hasHeader(headers: Record<string, string>, expected: string): boolean {
    const names = Object.keys(headers);
    for (const name of names) {
      if (name.toLowerCase() === expected.toLowerCase()) return true;
    }
    return false;
  }
}
