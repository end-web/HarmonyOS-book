import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { AuthService } from './AuthService';
import { CloudBackupService, CloudBackupOptions, CloudBackupResult, CloudBackupError,
  CloudBackupErrorCode } from './CloudBackupService';

const DAY_MS: number = 24 * 60 * 60 * 1000;
const CHECK_MS: number = 60 * 1000;

/** 仅存本机 Preferences，不进入任何备份快照。账号键使用摘要。 */
export class AutoBackupSettings {
  enabled: boolean = false;
  intervalDays: number = 1;
  lastSuccessAt: number = 0;
  digest: string = '';
  nextCheckAt: number = 0;
  failures: number = 0;
  errorCode: number = 0;
  systemCode: number = 0;
  trusted: boolean = false;
  needsDecision: boolean = false;

  static parse(raw: string): AutoBackupSettings {
    const result = new AutoBackupSettings();
    try {
      const value: AutoBackupSettings = JSON.parse(raw);
      if (!value || typeof value !== 'object') return result;
      result.enabled = value.enabled === true;
      result.intervalDays = value.intervalDays === 3 || value.intervalDays === 7 ? value.intervalDays : 1;
      result.lastSuccessAt = AutoBackupSettings.time(value.lastSuccessAt);
      result.nextCheckAt = AutoBackupSettings.time(value.nextCheckAt);
      result.digest = typeof value.digest === 'string' && new RegExp('^[0-9a-f]{64}$').test(value.digest)
        ? value.digest : '';
      result.failures = Number.isInteger(value.failures) ? Math.max(0, Math.min(8, value.failures)) : 0;
      result.errorCode = Number.isInteger(value.errorCode) ? value.errorCode : 0;
      result.systemCode = Number.isInteger(value.systemCode) ? value.systemCode : 0;
      result.trusted = value.trusted === true;
      result.needsDecision = value.needsDecision === true;
    } catch (_error) { /* 损坏的配置回到关闭状态，不能意外授权上传。 */ }
    return result;
  }

  private static time(value: number): number {
    return Number.isSafeInteger(value) && value > 0 ? value : 0;
  }
}

@ObservedV2
export class AutoBackupService {
  private static singleton: AutoBackupService | null = null;

  static get instance(): AutoBackupService {
    if (!AutoBackupService.singleton) AutoBackupService.singleton = new AutoBackupService();
    return AutoBackupService.singleton;
  }

  @Trace settings: AutoBackupSettings = new AutoBackupSettings();
  @Trace accountId: string = '';
  @Trace running: boolean = false;
  @Trace configuring: boolean = false;
  @Trace storageFailed: boolean = false;
  private store: preferences.Preferences | null = null;
  private accountKey: string = '';
  private foreground: boolean = false;
  private timer: number = -1;
  private task: Promise<void> | null = null;
  private manualHolds: number = 0;
  private context: common.Context | null = null;

  setForeground(context: common.Context, foreground: boolean): void {
    this.context = context;
    this.foreground = foreground;
    if (this.timer !== -1) clearTimeout(this.timer);
    this.timer = -1;
    if (!foreground) {
      if (this.running) CloudBackupService.instance.cancel();
      return;
    }
    // 冷启动和回前台留出首屏及服务恢复时间，不阻塞播放和阅读。
    this.schedule(10000);
  }

  private schedule(delay: number): void {
    if (!this.foreground) return;
    if (this.timer !== -1) clearTimeout(this.timer);
    this.timer = setTimeout((): void => {
      this.timer = -1;
      const context = this.context;
      if (context) this.check(context).finally((): void => this.schedule(CHECK_MS));
    }, delay);
  }

  async refresh(context: common.Context): Promise<void> {
    if (this.running || this.configuring) return;
    try {
      await this.load(context);
    } catch (_error) {
      this.storageFailed = true;
    }
  }

  private async load(context: common.Context): Promise<void> {
    const auth = AuthService.instance;
    const accountId = auth.isLoggedIn ? auth.openID : '';
    if (this.accountId === accountId && (this.store || !accountId)) return;
    this.accountId = '';
    this.accountKey = '';
    this.settings = new AutoBackupSettings();
    if (!accountId) return;
    const store = await preferences.getPreferences(context, { name: 'auto_backup_local' });
    const md = cryptoFramework.createMd('SHA256');
    await md.update({ data: new util.TextEncoder().encodeInto(accountId) });
    const digest = await md.digest();
    let key = '';
    for (const byte of digest.data) key += byte.toString(16).padStart(2, '0');
    const raw = await store.get(key, '');
    if (!auth.isLoggedIn || auth.openID !== accountId) return;
    this.store = store;
    this.accountKey = key;
    this.settings = AutoBackupSettings.parse(typeof raw === 'string' ? raw : '');
    this.accountId = accountId;
    this.storageFailed = false;
  }

  private currentAccount(): boolean {
    return this.accountId.length > 0 && AuthService.instance.isLoggedIn &&
      AuthService.instance.openID === this.accountId;
  }

  private copySettings(): AutoBackupSettings {
    return AutoBackupSettings.parse(JSON.stringify(this.settings));
  }

  private async save(next: AutoBackupSettings): Promise<void> {
    const store = this.store;
    if (!store || !this.currentAccount()) throw new CloudBackupError(CloudBackupErrorCode.ACCOUNT_CHANGED);
    const accountId = this.accountId;
    const key = this.accountKey;
    const previous = JSON.stringify(this.settings);
    try {
      await store.put(key, JSON.stringify(next));
      await store.flush();
    } catch (error) {
      // flush 失败不能让 Preferences 内存缓存保留尚未保存的开启状态。
      await store.put(key, previous);
      this.storageFailed = true;
      throw new CloudBackupError(CloudBackupErrorCode.LOCAL_FAILURE);
    }
    if (this.accountId === accountId && this.currentAccount()) {
      this.settings = next;
      this.storageFailed = false;
    }
  }

  /** 手动操作接管前等自动任务完全释放云同步监听及账号互斥锁。 */
  async pauseForManual(): Promise<void> {
    this.manualHolds++;
    if (this.running) CloudBackupService.instance.cancel();
    if (this.task) await this.task;
  }

  resumeAfterManual(): void {
    this.manualHolds = Math.max(0, this.manualHolds - 1);
  }

  async configure(context: common.Context, enabled: boolean, intervalDays: number): Promise<void> {
    if (this.configuring) return;
    this.configuring = true;
    await this.pauseForManual();
    try {
      await this.load(context);
      const next = this.copySettings();
      const wasEnabled = next.enabled;
      next.enabled = enabled;
      next.intervalDays = intervalDays === 3 || intervalDays === 7 ? intervalDays : 1;
      next.nextCheckAt = enabled && !wasEnabled ? 0 : next.lastSuccessAt + next.intervalDays * DAY_MS;
      next.failures = 0;
      next.errorCode = 0;
      next.systemCode = 0;
      await this.save(next);
    } finally {
      this.resumeAfterManual();
      this.configuring = false;
    }
    if (enabled) this.check(context);
  }

  check(context: common.Context): Promise<void> {
    if (this.task) return this.task;
    if (!this.foreground || this.manualHolds > 0 || this.configuring) return Promise.resolve();
    this.running = true;
    this.task = this.run(context).catch((): void => {
      this.storageFailed = true;
    }).finally((): void => {
      this.running = false;
      this.task = null;
    });
    return this.task;
  }

  private async run(context: common.Context): Promise<void> {
    const auth = AuthService.instance;
    if (auth.dataOperation || auth.logging || auth.restoring) return;
    await this.load(context);
    if (this.storageFailed || !this.currentAccount() || !this.settings.enabled || this.settings.needsDecision ||
      Date.now() < this.settings.nextCheckAt || this.manualHolds > 0 || !this.foreground) return;
    if (auth.dataOperation || auth.logging || auth.restoring) return;
    const accountId = this.accountId;
    const options = new CloudBackupOptions();
    options.previousDigest = this.settings.digest;
    options.protectExisting = !this.settings.trusted;
    try {
      const result = await CloudBackupService.instance.backup(context, options);
      if (!this.currentAccount() || accountId !== this.accountId) return;
      const next = this.copySettings();
      if (result.uploaded) {
        next.lastSuccessAt = result.exportedAt;
        next.digest = result.digest;
        next.trusted = true;
      }
      next.nextCheckAt = Date.now() + next.intervalDays * DAY_MS;
      next.errorCode = 0;
      next.systemCode = 0;
      next.failures = 0;
      await this.save(next);
    } catch (error) {
      if (!this.currentAccount() || accountId !== this.accountId) return;
      const failure: CloudBackupError = error;
      const next = this.copySettings();
      next.errorCode = failure.code ?? CloudBackupErrorCode.LOCAL_FAILURE;
      next.systemCode = failure.systemCode ?? 0;
      next.needsDecision = failure.code === CloudBackupErrorCode.EXISTING_BACKUP;
      next.failures = Math.min(next.failures + 1, 8);
      // 5 分钟起指数退避，上限 6 小时；取消不会在下一次前台检查立刻重启。
      next.nextCheckAt = Date.now() + Math.min(5 * 60 * 1000 * Math.pow(2, next.failures - 1), 6 * 60 * 60 * 1000);
      await this.save(next);
    }
  }

  async recordManualSuccess(context: common.Context, result: CloudBackupResult): Promise<void> {
    try {
      await this.load(context);
      if (!this.currentAccount() || this.accountId !== result.accountId || !result.uploaded) return;
      const next = this.copySettings();
      next.trusted = true;
      next.needsDecision = false;
      next.lastSuccessAt = result.exportedAt;
      next.digest = result.digest;
      next.nextCheckAt = Date.now() + next.intervalDays * DAY_MS;
      next.failures = 0;
      next.errorCode = 0;
      next.systemCode = 0;
      await this.save(next);
    } catch (_error) {
      // 云端已经成功，调度配置保存失败单独显示，不能把上传谎报为失败。
      this.storageFailed = true;
    }
  }

  /** 云恢复完成只解除新设备保护，不伪造本机上传成功时间。 */
  async recordRestoreSuccess(context: common.Context, accountId: string): Promise<void> {
    try {
      await this.load(context);
      if (!this.currentAccount() || this.accountId !== accountId) return;
      const next = this.copySettings();
      next.trusted = true;
      next.needsDecision = false;
      next.digest = '';
      next.nextCheckAt = Date.now() + next.intervalDays * DAY_MS;
      next.errorCode = 0;
      next.systemCode = 0;
      next.failures = 0;
      await this.save(next);
    } catch (_error) { this.storageFailed = true; }
  }
}
