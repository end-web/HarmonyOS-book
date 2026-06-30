import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';

const STORE_NAME = 'listenbook_stats';
const KEY_DAILY_STATS = 'daily_usage_stats_v1';

export const EVT_USAGE_STATS_UPDATED = 'app.usageStats.updated';

export interface DailyUsageStats {
  day: string;
  listenSeconds: number;
  readSeconds: number;
}

export interface UsageStatsBucket {
  label: string;
  listenSeconds: number;
  readSeconds: number;
}

export interface UsageStatsSummary {
  todaySeconds: number;
  weekSeconds: number;
  monthSeconds: number;
  totalSeconds: number;
}

export class StatsService {
  private static store: preferences.Preferences | null = null;
  private static initPromise: Promise<void> | null = null;

  static async init(context: common.BaseContext): Promise<void> {
    if (StatsService.store) return;
    if (!StatsService.initPromise) {
      StatsService.initPromise = preferences.getPreferences(context, { name: STORE_NAME }).then((s) => {
        StatsService.store = s;
      });
    }
    await StatsService.initPromise;
  }

  private static async ensureStore(): Promise<preferences.Preferences> {
    if (!StatsService.store && StatsService.initPromise) {
      await StatsService.initPromise;
    }
    if (!StatsService.store) {
      throw new Error('StatsService not initialized');
    }
    return StatsService.store;
  }

  static async addListenSeconds(seconds: number): Promise<void> {
    await StatsService.addSeconds(seconds, true);
  }

  static async addReadSeconds(seconds: number): Promise<void> {
    await StatsService.addSeconds(seconds, false);
  }

  private static async addSeconds(seconds: number, isListen: boolean): Promise<void> {
    const delta = Math.floor(seconds);
    if (delta <= 0) return;
    const s = await StatsService.ensureStore();
    const stats = await StatsService.getAllDailyStats();
    const day = StatsService.formatDay(new Date());
    let item = stats.find((it) => it.day === day);
    if (!item) {
      item = { day, listenSeconds: 0, readSeconds: 0 };
      stats.push(item);
    }
    if (isListen) {
      item.listenSeconds += delta;
    } else {
      item.readSeconds += delta;
    }
    StatsService.trimStats(stats);
    await s.put(KEY_DAILY_STATS, JSON.stringify(stats));
    await s.flush();
    emitter.emit(EVT_USAGE_STATS_UPDATED, { data: { day } });
  }

  static async getAllDailyStats(): Promise<DailyUsageStats[]> {
    const s = await StatsService.ensureStore();
    const raw = await s.get(KEY_DAILY_STATS, '[]') as string;
    try {
      const list = JSON.parse(raw) as DailyUsageStats[];
      if (!Array.isArray(list)) return [];
      const out: DailyUsageStats[] = [];
      for (const it of list) {
        if (!it || !it.day) continue;
        const listenSeconds = it.listenSeconds !== undefined ? it.listenSeconds : 0;
        const readSeconds = it.readSeconds !== undefined ? it.readSeconds : 0;
        out.push({
          day: it.day,
          listenSeconds: Math.max(0, Math.floor(listenSeconds)),
          readSeconds: Math.max(0, Math.floor(readSeconds))
        });
      }
      return out;
    } catch (_e) {
      return [];
    }
  }

  static async getRecentDays(days: number): Promise<UsageStatsBucket[]> {
    const count = Math.max(1, days);
    const stats = await StatsService.getAllDailyStats();
    const map = StatsService.toMap(stats);
    const out: UsageStatsBucket[] = [];
    for (let i = count - 1; i >= 0; i--) {
      const date = StatsService.addDays(new Date(), -i);
      const day = StatsService.formatDay(date);
      const item = map.get(day);
      out.push({
        label: count <= 7 ? StatsService.weekdayLabel(date) : `${date.getMonth() + 1}/${date.getDate()}`,
        listenSeconds: item?.listenSeconds ?? 0,
        readSeconds: item?.readSeconds ?? 0
      });
    }
    return out;
  }

  static async getYearMonths(year: number): Promise<UsageStatsBucket[]> {
    const stats = await StatsService.getAllDailyStats();
    const out: UsageStatsBucket[] = [];
    for (let month = 0; month < 12; month++) {
      out.push({ label: `${month + 1}月`, listenSeconds: 0, readSeconds: 0 });
    }
    for (const item of stats) {
      const date = StatsService.parseDay(item.day);
      if (!date || date.getFullYear() !== year) continue;
      const idx = date.getMonth();
      out[idx].listenSeconds += item.listenSeconds;
      out[idx].readSeconds += item.readSeconds;
    }
    return out;
  }

  static async getSummary(): Promise<UsageStatsSummary> {
    const stats = await StatsService.getAllDailyStats();
    const today = StatsService.formatDay(new Date());
    const todaySeconds = StatsService.sum(stats.filter((it) => it.day === today));
    const weekStart = StatsService.formatDay(StatsService.addDays(new Date(), -6));
    const monthStart = StatsService.formatDay(StatsService.addDays(new Date(), -29));
    return {
      todaySeconds,
      weekSeconds: StatsService.sum(stats.filter((it) => it.day >= weekStart)),
      monthSeconds: StatsService.sum(stats.filter((it) => it.day >= monthStart)),
      totalSeconds: StatsService.sum(stats)
    };
  }

  private static trimStats(stats: DailyUsageStats[]): void {
    const start = StatsService.formatDay(StatsService.addDays(new Date(), -730));
    for (let i = stats.length - 1; i >= 0; i--) {
      if (stats[i].day < start) {
        stats.splice(i, 1);
      }
    }
    stats.sort((a, b) => a.day.localeCompare(b.day));
  }

  private static toMap(stats: DailyUsageStats[]): Map<string, DailyUsageStats> {
    const map = new Map<string, DailyUsageStats>();
    for (const item of stats) {
      map.set(item.day, item);
    }
    return map;
  }

  private static sum(stats: DailyUsageStats[]): number {
    return stats.reduce((acc, item) => acc + item.listenSeconds + item.readSeconds, 0);
  }

  private static addDays(date: Date, days: number): Date {
    const d = new Date(date.getFullYear(), date.getMonth(), date.getDate());
    d.setDate(d.getDate() + days);
    return d;
  }

  private static parseDay(day: string): Date | null {
    const parts = day.split('-');
    if (parts.length !== 3) return null;
    const y = Number(parts[0]);
    const m = Number(parts[1]);
    const d = Number(parts[2]);
    if (!y || !m || !d) return null;
    return new Date(y, m - 1, d);
  }

  private static formatDay(date: Date): string {
    const y = date.getFullYear();
    const m = (date.getMonth() + 1).toString().padStart(2, '0');
    const d = date.getDate().toString().padStart(2, '0');
    return `${y}-${m}-${d}`;
  }

  private static weekdayLabel(date: Date): string {
    const labels = ['日', '一', '二', '三', '四', '五', '六'];
    return labels[date.getDay()];
  }
}
