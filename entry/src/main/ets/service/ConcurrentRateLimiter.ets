/**
 * ConcurrentRateLimiter - 请求速率限制器（Legado concurrentRate 对齐）
 *
 * 格式：
 *  - "500"       → 每 500ms 最多 1 个请求
 *  - "3/1000"    → 每 1000ms 最多 3 个请求
 *  - "5/60000"   → 每 60000ms 最多 5 个请求
 *
 * 使用方式：
 *  const limiter = getRateLimiter('3/1000');
 *  await limiter.acquire();  // 等待直到可以发送请求
 */

interface RateLimiterConfig {
  maxCount: number;   // 窗口内最大请求数
  windowMs: number;   // 窗口大小（毫秒）
}

class ConcurrentRateLimiterImpl {
  private maxCount: number;
  private windowMs: number;
  private timestamps: number[] = [];

  constructor(config: RateLimiterConfig) {
    this.maxCount = config.maxCount;
    this.windowMs = config.windowMs;
  }

  /**
   * 获取一个请求许可。如果超出速率限制，等待直到可以发送。
   */
  async acquire(): Promise<void> {
    const now = Date.now();
    // 清理过期的时间戳
    this.timestamps = this.timestamps.filter((t) => now - t < this.windowMs);

    if (this.timestamps.length >= this.maxCount) {
      // 需要等待：等到最早的请求过期
      const oldest = this.timestamps[0];
      const waitMs = this.windowMs - (now - oldest) + 10; // +10ms 余量
      if (waitMs > 0) {
        await new Promise<void>((resolve) => setTimeout(resolve, waitMs));
      }
      // 重新清理
      const now2 = Date.now();
      this.timestamps = this.timestamps.filter((t) => now2 - t < this.windowMs);
    }

    this.timestamps.push(Date.now());
  }
}

// 缓存：config string → limiter 实例
const limiterCache: Map<string, ConcurrentRateLimiterImpl> = new Map();

/**
 * 获取或创建速率限制器
 * @param rateConfig Legado concurrentRate 格式："ms" 或 "count/ms"
 */
export function getRateLimiter(rateConfig: string | undefined): ConcurrentRateLimiterImpl | null {
  if (!rateConfig || !rateConfig.trim()) return null;

  const key = rateConfig.trim();
  if (limiterCache.has(key)) return limiterCache.get(key)!;

  const config = parseRateConfig(key);
  if (!config) return null;

  const limiter = new ConcurrentRateLimiterImpl(config);
  limiterCache.set(key, limiter);
  return limiter;
}

function parseRateConfig(config: string): RateLimiterConfig | null {
  const trimmed = config.trim();
  if (!trimmed) return null;

  // "count/ms" 格式
  const slashIdx = trimmed.indexOf('/');
  if (slashIdx > 0) {
    const count = parseInt(trimmed.substring(0, slashIdx), 10);
    const ms = parseInt(trimmed.substring(slashIdx + 1), 10);
    if (!isNaN(count) && !isNaN(ms) && count > 0 && ms > 0) {
      return { maxCount: count, windowMs: ms };
    }
  }

  // "ms" 格式（每 Nms 最多 1 个请求）
  const ms = parseInt(trimmed, 10);
  if (!isNaN(ms) && ms > 0) {
    return { maxCount: 1, windowMs: ms };
  }

  return null;
}

/**
 * 简单并发信号量 — 限制同时进行的异步操作数量。
 * 用于多源搜索等场景，防止一次性发起过多网络请求。
 *
 * 用法：
 *   const sem = new SimpleSemaphore(6);
 *   await sem.acquire();
 *   try { ... } finally { sem.release(); }
 */
export class SimpleSemaphore {
  private permits: number;
  private waiters: Array<() => void> = [];

  constructor(maxConcurrency: number) {
    this.permits = maxConcurrency;
  }

  async acquire(): Promise<void> {
    if (this.permits > 0) {
      this.permits--;
      return;
    }
    await new Promise<void>((resolve: () => void): void => {
      this.waiters.push(resolve);
    });
  }

  release(): void {
    const next = this.waiters.shift();
    if (next) {
      next();
    } else {
      this.permits++;
    }
  }
}
