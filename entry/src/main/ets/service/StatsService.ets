import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';

const STORE_NAME = 'listenbook_stats';
const KEY_BOOK_USAGE = 'book_usage_records_v2';

export const EVT_USAGE_STATS_UPDATED = 'app.usageStats.updated';

export interface BookUsageInput {
  bookId: string;
  title: string;
  author?: string;
  cover?: string;
  sourceUrl?: string;
  bookUrl?: string;
}

export interface BookUsageDay {
  day: string;
  listenSeconds: number;
}

export interface BookUsageStats {
  bookId: string;
  title: string;
  author: string;
  cover: string;
  listenSeconds: number;
  updatedAt: number;
  days: BookUsageDay[];
  sourceUrl?: string;
  bookUrl?: string;
}

export interface DailyUsageStats {
  day: string;
  listenSeconds: number;
}

export interface UsageStatsBucket {
  label: string;
  listenSeconds: number;
}

export interface UsageStatsSummary {
  todaySeconds: number;
  weekSeconds: number;
  monthSeconds: number;
  totalSeconds: number;
}

export interface HeatPoint {
  day: string;
  seconds: number;
}

/** 一次读盘算全部指标的整包快照,避免页面分多次读 store 时被并发写撕裂成不一致状态 */
export interface StatsBundle {
  records: BookUsageStats[];
  summary: UsageStatsSummary;
  streak: number;
  heatDays: HeatPoint[];
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

  static async addListenSeconds(seconds: number, book: BookUsageInput): Promise<void> {
    await StatsService.addSeconds(seconds, book);
  }

  private static async addSeconds(seconds: number, book: BookUsageInput): Promise<void> {
    const delta = Math.floor(seconds);
    if (delta <= 0 || !book.bookId) return;
    const s = await StatsService.ensureStore();
    const records = await StatsService.getBookStats();
    const day = StatsService.formatDay(new Date());
    let rec = records.find((item) => item.bookId === book.bookId);
    if (!rec) {
      rec = {
        bookId: book.bookId,
        title: book.title || '未知书籍',
        author: book.author || '',
        cover: book.cover || '',
        listenSeconds: 0,
        updatedAt: Date.now(),
        days: [],
        sourceUrl: book.sourceUrl || '',
        bookUrl: book.bookUrl || ''
      };
      records.push(rec);
    }

    rec.title = book.title || rec.title;
    rec.author = book.author || rec.author;
    rec.cover = book.cover || rec.cover;
    rec.updatedAt = Date.now();
    if (book.sourceUrl) rec.sourceUrl = book.sourceUrl;
    if (book.bookUrl) rec.bookUrl = book.bookUrl;
    let dayItem = rec.days.find((item) => item.day === day);
    if (!dayItem) {
      dayItem = { day, listenSeconds: 0 };
      rec.days.push(dayItem);
    }
    rec.listenSeconds += delta;
    dayItem.listenSeconds += delta;
    rec.days = StatsService.trimDays(rec.days);
    records.sort((a, b) => b.updatedAt - a.updatedAt);
    await s.put(KEY_BOOK_USAGE, JSON.stringify(records));
    await s.flush();
    emitter.emit(EVT_USAGE_STATS_UPDATED, { data: { day, bookId: book.bookId } });
  }

  static async getBookStats(): Promise<BookUsageStats[]> {
    const s = await StatsService.ensureStore();
    const raw = await s.get(KEY_BOOK_USAGE, '[]') as string;
    try {
      const list = JSON.parse(raw) as BookUsageStats[];
      if (!Array.isArray(list)) return [];
      return list
        .filter((item) => !!item && !!item.bookId)
        .map((item): BookUsageStats => {
          const days = Array.isArray(item.days) ? item.days : [];
          return {
            bookId: item.bookId,
            title: item.title || '未知书籍',
            author: item.author || '',
            cover: item.cover || '',
            listenSeconds: Math.max(0, Math.floor(item.listenSeconds || 0)),
            updatedAt: item.updatedAt || 0,
            days: StatsService.trimDays(days),
            sourceUrl: item.sourceUrl || '',
            bookUrl: item.bookUrl || ''
          };
        })
        .sort((a, b) => b.updatedAt - a.updatedAt);
    } catch (_e) {
      return [];
    }
  }

  static async removeBookStats(bookIds: string[]): Promise<void> {
    if (bookIds.length === 0) return;
    const s = await StatsService.ensureStore();
    const deleted = new Set(bookIds);
    const next = (await StatsService.getBookStats()).filter((item) => !deleted.has(item.bookId));
    await s.put(KEY_BOOK_USAGE, JSON.stringify(next));
    await s.flush();
    emitter.emit(EVT_USAGE_STATS_UPDATED, { data: { day: StatsService.formatDay(new Date()) } });
  }

  static async clearBookStats(): Promise<void> {
    const s = await StatsService.ensureStore();
    await s.put(KEY_BOOK_USAGE, '[]');
    await s.flush();
    emitter.emit(EVT_USAGE_STATS_UPDATED, { data: { day: StatsService.formatDay(new Date()) } });
  }

  static async getAllDailyStats(): Promise<DailyUsageStats[]> {
    return StatsService.aggregateDaily(await StatsService.getBookStats());
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
        listenSeconds: item?.listenSeconds ?? 0
      });
    }
    return out;
  }

  /** 连续 N 天的每日总时长（含 0 值），chronological（旧→新，末位为今天） */
  static async getDailyTotals(days: number): Promise<HeatPoint[]> {
    const count = Math.max(1, days);
    const stats = await StatsService.getAllDailyStats();
    const map = StatsService.toMap(stats);
    const out: HeatPoint[] = [];
    for (let i = count - 1; i >= 0; i--) {
      const date = StatsService.addDays(new Date(), -i);
      const day = StatsService.formatDay(date);
      const item = map.get(day);
      out.push({ day, seconds: item?.listenSeconds ?? 0 });
    }
    return out;
  }

  /** 截至今天的连续打卡天数（当天时长>0 才计入今天） */
  static async getStreakDays(): Promise<number> {
    const stats = await StatsService.getAllDailyStats();
    const map = StatsService.toMap(stats);
    let streak = 0;
    for (let i = 0; i < 730; i++) {
      const day = StatsService.formatDay(StatsService.addDays(new Date(), -i));
      const item = map.get(day);
      const seconds = item?.listenSeconds ?? 0;
      if (seconds > 0) {
        streak++;
      } else if (i === 0) {
        // 今天还没收听，从昨天继续算
        continue;
      } else {
        break;
      }
    }
    return streak;
  }

  static async getYearMonths(year: number): Promise<UsageStatsBucket[]> {
    const stats = await StatsService.getAllDailyStats();
    const out: UsageStatsBucket[] = [];
    for (let month = 0; month < 12; month++) {
      out.push({ label: `${month + 1}月`, listenSeconds: 0 });
    }
    for (const item of stats) {
      const date = StatsService.parseDay(item.day);
      if (!date || date.getFullYear() !== year) continue;
      const idx = date.getMonth();
      out[idx].listenSeconds += item.listenSeconds;
    }
    return out;
  }

  static async getSummary(): Promise<UsageStatsSummary> {
    const stats = await StatsService.getAllDailyStats();
    const today = StatsService.formatDay(new Date());
    const weekStart = StatsService.formatDay(StatsService.addDays(new Date(), -6));
    const monthStart = StatsService.formatDay(StatsService.addDays(new Date(), -29));
    return {
      todaySeconds: StatsService.sum(stats.filter((item) => item.day === today)),
      weekSeconds: StatsService.sum(stats.filter((item) => item.day >= weekStart)),
      monthSeconds: StatsService.sum(stats.filter((item) => item.day >= monthStart)),
      totalSeconds: StatsService.sum(stats)
    };
  }

  /**
   * 一次读盘 → 从同一份 records 快照算出所有指标。
   * 页面用这个替代分散的 getBookStats/getSummary/getStreakDays/getDailyTotals 多次读盘,
   * 保证 6 个展示值内部一致(不会出现"今日有值但累计/本数/连续为 0"的撕裂)。
   */
  static async getStatsBundle(heatmapDays: number): Promise<StatsBundle> {
    const records = await StatsService.getBookStats();
    const daily = StatsService.aggregateDaily(records);
    const map = StatsService.toMap(daily);
    return {
      records,
      summary: StatsService.computeSummary(map),
      streak: StatsService.computeStreak(map),
      heatDays: StatsService.computeHeatDays(map, heatmapDays)
    };
  }

  private static computeSummary(map: Map<string, DailyUsageStats>): UsageStatsSummary {
    const today = StatsService.formatDay(new Date());
    const weekStart = StatsService.formatDay(StatsService.addDays(new Date(), -6));
    const monthStart = StatsService.formatDay(StatsService.addDays(new Date(), -29));
    let todaySeconds = 0;
    let weekSeconds = 0;
    let monthSeconds = 0;
    let totalSeconds = 0;
    for (const item of map.values()) {
      const secs = item.listenSeconds;
      totalSeconds += secs;
      if (item.day === today) todaySeconds += secs;
      if (item.day >= weekStart) weekSeconds += secs;
      if (item.day >= monthStart) monthSeconds += secs;
    }
    return { todaySeconds, weekSeconds, monthSeconds, totalSeconds };
  }

  private static computeStreak(map: Map<string, DailyUsageStats>): number {
    let streak = 0;
    for (let i = 0; i < 730; i++) {
      const day = StatsService.formatDay(StatsService.addDays(new Date(), -i));
      const item = map.get(day);
      const seconds = item?.listenSeconds ?? 0;
      if (seconds > 0) {
        streak++;
      } else if (i === 0) {
        continue;
      } else {
        break;
      }
    }
    return streak;
  }

  private static computeHeatDays(map: Map<string, DailyUsageStats>, days: number): HeatPoint[] {
    const count = Math.max(1, days);
    const out: HeatPoint[] = [];
    for (let i = count - 1; i >= 0; i--) {
      const date = StatsService.addDays(new Date(), -i);
      const day = StatsService.formatDay(date);
      const item = map.get(day);
      out.push({ day, seconds: item?.listenSeconds ?? 0 });
    }
    return out;
  }

  private static aggregateDaily(records: BookUsageStats[]): DailyUsageStats[] {
    const map = new Map<string, DailyUsageStats>();
    for (const record of records) {
      for (const day of record.days) {
        let item = map.get(day.day);
        if (!item) {
          item = { day: day.day, listenSeconds: 0 };
          map.set(day.day, item);
        }
        item.listenSeconds += Math.max(0, Math.floor(day.listenSeconds || 0));
      }
    }
    return Array.from(map.values()).sort((a, b) => a.day.localeCompare(b.day));
  }

  private static trimDays(days: BookUsageDay[]): BookUsageDay[] {
    const start = StatsService.formatDay(StatsService.addDays(new Date(), -730));
    return days
      .filter((item) => item && item.day >= start)
      .map((item): BookUsageDay => ({
        day: item.day,
        listenSeconds: Math.max(0, Math.floor(item.listenSeconds || 0))
      }))
      .sort((a, b) => a.day.localeCompare(b.day));
  }

  private static toMap(stats: DailyUsageStats[]): Map<string, DailyUsageStats> {
    const map = new Map<string, DailyUsageStats>();
    for (const item of stats) {
      map.set(item.day, item);
    }
    return map;
  }

  private static sum(stats: DailyUsageStats[]): number {
    return stats.reduce((acc, item) => acc + item.listenSeconds, 0);
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
