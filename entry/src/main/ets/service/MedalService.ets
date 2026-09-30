import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { emitter } from '@kit.BasicServicesKit';
import { MEDALS, MedalAward, MedalDefinition, MedalSnapshot } from '../model/Medal';
import { StatsService, EVT_USAGE_STATS_UPDATED } from './StatsService';

/** 与本地收听统计同作用域，登录只控制展示，不按账号重复累计。 */
@ObservedV2
export class MedalService {
  private static singleton: MedalService | null = null;
  static get instance(): MedalService {
    if (MedalService.singleton === null) MedalService.singleton = new MedalService();
    return MedalService.singleton;
  }

  @Trace ready: boolean = false;
  @Trace failed: boolean = false;
  @Trace totalSeconds: number = 0;
  @Trace selectedMedalId: string = '';
  @Trace awards: MedalAward[] = [];
  @Trace newAwardCount: number = 0;
  private store: preferences.Preferences | undefined = undefined;
  private state: MedalSnapshot = new MedalSnapshot();
  private initPromise: Promise<void> | undefined = undefined;
  private queue: Promise<void> = Promise.resolve();
  private listening: boolean = false;
  private pendingAwards: MedalAward[] = [];
  private onStatsUpdated = (event: emitter.EventData): void => {
    // 事件发出时立即取缓存：删除记录排在后面时，也不会丢掉刚达标的勋章。
    this.refreshUnlocks(event.data?.historical === true).catch((error: Error): void => {
      this.failed = true;
      console.warn(`[MedalService] unlock failed: ${error.message}`);
    });
  };

  async init(context: common.Context): Promise<void> {
    if (this.ready) return;
    if (this.initPromise === undefined) {
      this.initPromise = this.initialize(context).catch((error: Error): void => {
        this.failed = true;
        this.initPromise = undefined;
        throw error;
      });
    }
    await this.initPromise;
  }

  private async initialize(context: common.Context): Promise<void> {
    await StatsService.init(context);
    this.store = await preferences.getPreferences(context, { name: 'listenbook_medals' });
    const raw = await this.store.get('medal_state_v1', '');
    if (typeof raw !== 'string') throw new Error('Invalid medal storage');
    const saved: MedalSnapshot = raw.length > 0 ? JSON.parse(raw) : new MedalSnapshot();
    if (!MedalService.isValidSnapshot(saved)) throw new Error('Invalid medal snapshot');
    this.state = MedalService.copy(saved);
    // 保存迁移默认项，也区分“从未选择”与用户主动取消佩戴的空 ID。
    await this.save(this.state);
    if (!this.listening) {
      emitter.on(EVT_USAGE_STATS_UPDATED, this.onStatsUpdated);
      this.listening = true;
    }
    await this.refreshUnlocks(true);
    this.ready = true;
    this.failed = false;
  }

  private enqueue(action: () => Promise<void>): Promise<void> {
    const task = this.queue.then(action);
    this.queue = task.catch((): void => {});
    return task;
  }

  refreshUnlocks(historical: boolean = false): Promise<void> {
    const stats = StatsService.getCachedStatsBundle(1);
    if (stats === undefined) return Promise.reject(new Error('Listening statistics unavailable'));
    const seconds = stats.summary.totalSeconds;
    return this.enqueue(async (): Promise<void> => {
      this.totalSeconds = seconds;
      const next = MedalService.copy(this.state);
      for (const pending of this.pendingAwards) {
        if (!next.awards.some((award: MedalAward): boolean => award.medalId === pending.medalId)) {
          next.awards.push(pending);
        }
      }
      let added = 0;
      for (const medal of MEDALS) {
        if (seconds >= medal.hours * 3600 && !next.awards.some((award: MedalAward): boolean => award.medalId === medal.id)) {
          next.awards.push(new MedalAward(medal.id, historical ? 0 : Date.now(), historical));
          added++;
        }
      }
      if (added > 0 || this.failed || this.pendingAwards.length > 0) {
        this.pendingAwards = next.awards.slice();
        await this.save(next);
        this.pendingAwards = [];
      }
      if (!historical) this.newAwardCount += added;
      this.failed = false;
    });
  }

  isUnlocked(id: string): boolean {
    return this.awards.some((award: MedalAward): boolean => award.medalId === id);
  }

  selected(): MedalDefinition | undefined {
    return MEDALS.find((medal: MedalDefinition): boolean => medal.id === this.selectedMedalId);
  }

  equipMedal(id: string): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      if (!this.ready || (id !== '' && !this.isUnlocked(id))) throw new Error('Medal is locked');
      const next = MedalService.copy(this.state);
      next.selectedMedalId = id;
      await this.save(next);
    });
  }

  private async save(next: MedalSnapshot): Promise<void> {
    const store = this.store;
    if (store === undefined) throw new Error('MedalService not initialized');
    try {
      await store.put('medal_state_v1', JSON.stringify(next));
      await store.flush();
    } catch (error) {
      this.failed = true;
      // 回滚 Preferences 内存缓存，失败的佩戴操作不能被后续 flush 意外提交。
      try { await store.put('medal_state_v1', JSON.stringify(this.state)); } catch (_error) { /* 保留原始错误 */ }
      throw new Error(String(error));
    }
    this.state = MedalService.copy(next);
    this.awards = this.state.awards.slice();
    this.selectedMedalId = this.state.selectedMedalId;
  }

  async exportSnapshot(context: common.Context, totalSeconds: number): Promise<MedalSnapshot> {
    await this.queue;
    let saved: MedalSnapshot = this.state;
    if (!this.ready) {
      // 备份使用已经清洗的统计副本，不强制初始化原始统计，避免一条旧记录损坏阻断备份。
      const store = await preferences.getPreferences(context, { name: 'listenbook_medals' });
      const raw = await store.get('medal_state_v1', '');
      if (typeof raw !== 'string') throw new Error('Invalid medal storage');
      saved = raw.length > 0 ? JSON.parse(raw) : new MedalSnapshot();
      if (!MedalService.isValidSnapshot(saved)) throw new Error('Invalid medal snapshot');
    }
    const snapshot = MedalService.copy(saved);
    for (const medal of MEDALS) {
      if (totalSeconds >= medal.hours * 3600 && !snapshot.awards.some((award: MedalAward): boolean => award.medalId === medal.id)) {
        snapshot.awards.push(new MedalAward(medal.id));
      }
    }
    return snapshot;
  }

  async restoreSnapshot(context: common.Context, saved: MedalSnapshot | undefined): Promise<void> {
    if (saved !== undefined && !MedalService.isValidSnapshot(saved)) throw new Error('Invalid medal backup');
    await this.init(context);
    await this.enqueue(async (): Promise<void> => {
      const next = MedalService.copy(this.state);
      if (saved !== undefined) {
        for (const award of saved.awards) {
          const existing = next.awards.find((item: MedalAward): boolean => item.medalId === award.medalId);
          if (existing === undefined) next.awards.push(new MedalAward(award.medalId, award.unlockedAt, award.historical));
          else if (existing.historical && !award.historical) {
            existing.unlockedAt = award.unlockedAt;
            existing.historical = false;
          }
        }
        next.selectedMedalId = saved.selectedMedalId;
      }
      await this.save(next);
    });
    await this.refreshUnlocks(true);
  }

  async flush(): Promise<void> {
    await this.queue;
    if (this.ready && this.failed) await this.refreshUnlocks();
  }

  private static copy(value: MedalSnapshot): MedalSnapshot {
    const copy = new MedalSnapshot();
    copy.selectedMedalId = value.selectedMedalId;
    copy.awards = value.awards.map((award: MedalAward): MedalAward =>
      new MedalAward(award.medalId, award.unlockedAt, award.historical));
    return copy;
  }

  static isValidSnapshot(value: MedalSnapshot): boolean {
    if (!value || value.version !== 1 || typeof value.selectedMedalId !== 'string' ||
      !Array.isArray(value.awards) || value.awards.length < 1 || value.awards.length > MEDALS.length) return false;
    const seen = new Set<string>();
    for (const award of value.awards) {
      if (!award || !MEDALS.some((medal: MedalDefinition): boolean => medal.id === award.medalId) ||
        seen.has(award.medalId) || !Number.isSafeInteger(award.unlockedAt) || award.unlockedAt < 0 ||
        typeof award.historical !== 'boolean' || (!award.historical && award.unlockedAt === 0)) return false;
      seen.add(award.medalId);
    }
    return seen.has('national_day') && (value.selectedMedalId === '' || seen.has(value.selectedMedalId));
  }
}
