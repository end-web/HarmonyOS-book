import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { Book } from '../model/Book';
import {
  LocalRuleBookInfoRule,
  LocalRuleContentRule,
  LocalRuleSearchRule,
  LocalRuleSource,
  LocalRuleSourceStatus,
  LocalRuleSourceType,
  LocalRuleTocRule
} from '../model/LocalRuleSource';
import { PreferenceBackupSnapshot, PreferenceService } from './PreferenceService';
import { BookUsageStats, StatsService } from './StatsService';
import { DataService } from './DataService';
import { LocalRuleSourceRepository } from './rulesource/LocalRuleSourceRepository';
import { GuangYuSourceIdentity } from './rulesource/guangyu/GuangYuSourceIdentity';
import { ShuShanSourceIdentity } from './rulesource/shushan/ShuShanSourceIdentity';
import { SourceDataService } from './SourceDataService';

const BACKUP_DIR: string = 'backup';
const BACKUP_FILE: string = 'listenbook_state.json';
const BACKUP_VERSION: number = 2;

/** 保存可迁移的解析定义；请求头会清洗，运行期 Cookie 和原始书源 JSON 不进入备份。 */
class BackupRuleSource {
  bookSourceUrl: string = '';
  bookSourceName: string = '';
  bookSourceType: number = LocalRuleSourceType.TEXT;
  bookSourceGroup: string = '';
  bookSourceComment: string = '';
  enabled: boolean = true;
  enabledExplore: boolean = false;
  enabledCookieJar: boolean = true;
  searchUrl: string = '';
  exploreUrl: string = '';
  header: string = '';
  loginUrl: string = '';
  loginUi: string = '';
  loginCheckJs: string = '';
  jsLib: string = '';
  variable: string = '';
  respondTime: number = 18000;
  concurrentRate: string = '';
  lastUpdateTime: number = 0;
  validationStatus: number = LocalRuleSourceStatus.UNCHECKED;
  validationMessage: string = '';
  ruleSearch: LocalRuleSearchRule | undefined = undefined;
  ruleBookInfo: LocalRuleBookInfoRule | undefined = undefined;
  ruleToc: LocalRuleTocRule | undefined = undefined;
  ruleContent: LocalRuleContentRule | undefined = undefined;
}

class AppBackupSnapshot {
  version: number = BACKUP_VERSION;
  exportedAt: number = 0;
  preferences: PreferenceBackupSnapshot = new PreferenceBackupSnapshot();
  stats: BookUsageStats[] = [];
  books: Book[] = [];
  ruleSources: BackupRuleSource[] = [];
}

export class AppBackupService {
  private static backupDir(context: common.Context): string {
    return `${context.filesDir}/${BACKUP_DIR}`;
  }

  private static backupPath(context: common.Context): string {
    return `${AppBackupService.backupDir(context)}/${BACKUP_FILE}`;
  }

  static async createSnapshot(context: common.Context): Promise<void> {
    await PreferenceService.init(context);
    await StatsService.init(context);
    DataService.setContext(context);
    const snapshot = new AppBackupSnapshot();
    snapshot.exportedAt = Date.now();
    snapshot.preferences = await PreferenceService.exportBackupSnapshot();
    snapshot.stats = (await StatsService.getBookStats())
      .filter((item: BookUsageStats) => !item.bookId.startsWith('import_'));
    snapshot.books = await DataService.exportBackupBookShells();
    try {
      await LocalRuleSourceRepository.init(context);
      const localSources = await LocalRuleSourceRepository.getAll();
      for (const source of localSources) {
        snapshot.ruleSources.push(AppBackupService.toBackupRuleSource(source));
      }
    } catch (error) {
      console.warn(`[AppBackupService] skip local rule backup: ${AppBackupService.errorMessage(error)}`);
    }

    const dir = AppBackupService.backupDir(context);
    try { await fileIo.mkdir(dir); } catch (_e) { /* 已存在 */ }
    const path = AppBackupService.backupPath(context);
    const tmp = path + '.tmp';
    const file = await fileIo.open(tmp,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, JSON.stringify(snapshot));
      try { await fileIo.fsync(file.fd); } catch (_e) { /* 部分文件系统不支持 */ }
    } finally {
      await fileIo.close(file);
    }
    await fileIo.moveFile(tmp, path);
  }

  static async restoreSnapshot(context: common.Context): Promise<boolean> {
    const path = AppBackupService.backupPath(context);
    let exists = false;
    try { exists = await fileIo.access(path); } catch (_e) { exists = false; }
    if (!exists) return false;
    const raw = await fileIo.readText(path);
    if (!raw) return false;
    const snapshot = JSON.parse(raw) as AppBackupSnapshot;
    if (!snapshot || (snapshot.version !== 1 && snapshot.version !== BACKUP_VERSION) ||
      !snapshot.preferences) return false;

    await PreferenceService.init(context);
    await StatsService.init(context);
    DataService.setContext(context);
    if (snapshot.version >= 2 && Array.isArray(snapshot.ruleSources)) {
      const localSources: LocalRuleSource[] = [];
      for (const backupSource of snapshot.ruleSources) {
        const source = AppBackupService.fromBackupRuleSource(backupSource);
        if (source !== undefined) localSources.push(source);
      }
      if (localSources.length > 0) {
        try {
          await LocalRuleSourceRepository.init(context);
          await LocalRuleSourceRepository.upsertMany(localSources);
          SourceDataService.invalidateLocalSources();
        } catch (error) {
          console.warn(`[AppBackupService] skip local rule restore: ${AppBackupService.errorMessage(error)}`);
        }
      }
    }
    await PreferenceService.restoreBackupSnapshot(snapshot.preferences);
    await StatsService.restoreBackupStats(Array.isArray(snapshot.stats) ? snapshot.stats : []);
    await DataService.restoreBackupBookShells(Array.isArray(snapshot.books) ? snapshot.books : []);
    return true;
  }

  private static toBackupRuleSource(source: LocalRuleSource): BackupRuleSource {
    const backup = new BackupRuleSource();
    backup.bookSourceUrl = source.bookSourceUrl;
    backup.bookSourceName = source.bookSourceName;
    backup.bookSourceType = source.bookSourceType;
    backup.bookSourceGroup = source.bookSourceGroup;
    backup.bookSourceComment = source.bookSourceComment;
    backup.enabled = source.enabled;
    backup.enabledExplore = source.enabledExplore;
    backup.enabledCookieJar = source.enabledCookieJar;
    backup.searchUrl = source.searchUrl;
    backup.exploreUrl = source.exploreUrl;
    backup.header = AppBackupService.sanitizeHeader(source.header);
    backup.loginUrl = source.loginUrl;
    backup.loginUi = source.loginUi;
    backup.loginCheckJs = source.loginCheckJs;
    backup.jsLib = source.jsLib;
    backup.variable = source.variable;
    backup.respondTime = source.respondTime;
    backup.concurrentRate = source.concurrentRate;
    backup.lastUpdateTime = source.lastUpdateTime;
    backup.validationStatus = source.validationStatus;
    backup.validationMessage = source.validationMessage;
    backup.ruleSearch = AppBackupService.copySearchRule(source.ruleSearch);
    backup.ruleBookInfo = AppBackupService.copyBookInfoRule(source.ruleBookInfo);
    backup.ruleToc = AppBackupService.copyTocRule(source.ruleToc);
    backup.ruleContent = AppBackupService.copyContentRule(source.ruleContent);
    return backup;
  }

  private static fromBackupRuleSource(backup: BackupRuleSource): LocalRuleSource | undefined {
    const sourceUrl = (backup.bookSourceUrl || '').trim();
    const sourceName = (backup.bookSourceName || '').trim();
    if (sourceUrl.length === 0 || sourceName.length === 0) return undefined;

    const source = new LocalRuleSource();
    source.bookSourceUrl = sourceUrl;
    source.bookSourceName = sourceName;
    source.bookSourceType = AppBackupService.validSourceType(backup.bookSourceType);
    source.bookSourceGroup = backup.bookSourceGroup || '';
    source.bookSourceComment = backup.bookSourceComment || '';
    source.enabled = backup.enabled === true;
    source.enabledExplore = backup.enabledExplore === true;
    source.enabledCookieJar = backup.enabledCookieJar !== false;
    source.searchUrl = backup.searchUrl || '';
    source.exploreUrl = backup.exploreUrl || '';
    source.header = AppBackupService.sanitizeHeader(backup.header || '');
    source.loginUrl = backup.loginUrl || '';
    source.loginUi = backup.loginUi || '';
    source.loginCheckJs = backup.loginCheckJs || '';
    source.jsLib = backup.jsLib || '';
    source.variable = backup.variable || '';
    source.respondTime = Number.isFinite(backup.respondTime) && backup.respondTime > 0
      ? backup.respondTime : 18000;
    source.concurrentRate = backup.concurrentRate || '';
    source.lastUpdateTime = Number.isFinite(backup.lastUpdateTime) ? backup.lastUpdateTime : 0;
    const savedStatus = AppBackupService.validStatus(backup.validationStatus);
    const usesNativeAdapter = GuangYuSourceIdentity.isSourceUrl(sourceUrl) ||
      ShuShanSourceIdentity.isSourceUrl(sourceUrl);
    if (savedStatus === LocalRuleSourceStatus.UNSUPPORTED && !usesNativeAdapter) {
      source.validationStatus = LocalRuleSourceStatus.UNSUPPORTED;
      source.validationMessage = backup.validationMessage || '书源包含当前版本不支持的能力';
      source.enabled = false;
    } else {
      source.validationStatus = LocalRuleSourceStatus.UNCHECKED;
      source.validationMessage = '恢复后等待重新测试';
    }

    if (backup.ruleSearch !== undefined) {
      source.ruleSearch = AppBackupService.copySearchRule(backup.ruleSearch);
    }
    if (backup.ruleBookInfo !== undefined) {
      source.ruleBookInfo = AppBackupService.copyBookInfoRule(backup.ruleBookInfo);
    }
    if (backup.ruleToc !== undefined) {
      source.ruleToc = AppBackupService.copyTocRule(backup.ruleToc);
    }
    if (backup.ruleContent !== undefined) {
      source.ruleContent = AppBackupService.copyContentRule(backup.ruleContent);
    }
    source.rawSourceJson = '';
    return source;
  }

  private static copySearchRule(source: LocalRuleSearchRule): LocalRuleSearchRule {
    const rule = new LocalRuleSearchRule();
    rule.bookList = source.bookList || '';
    rule.name = source.name || '';
    rule.author = source.author || '';
    rule.coverUrl = source.coverUrl || '';
    rule.bookUrl = source.bookUrl || '';
    rule.intro = source.intro || '';
    rule.kind = source.kind || '';
    rule.status = source.status || '';
    rule.lastChapter = source.lastChapter || '';
    rule.wordCount = source.wordCount || '';
    rule.updateTime = source.updateTime || '';
    return rule;
  }

  private static copyBookInfoRule(source: LocalRuleBookInfoRule): LocalRuleBookInfoRule {
    const rule = new LocalRuleBookInfoRule();
    rule.init = source.init || '';
    rule.name = source.name || '';
    rule.author = source.author || '';
    rule.coverUrl = source.coverUrl || '';
    rule.intro = source.intro || '';
    rule.kind = source.kind || '';
    rule.status = source.status || '';
    rule.lastChapter = source.lastChapter || '';
    rule.wordCount = source.wordCount || '';
    rule.updateTime = source.updateTime || '';
    rule.tocUrl = source.tocUrl || '';
    return rule;
  }

  private static copyTocRule(source: LocalRuleTocRule): LocalRuleTocRule {
    const rule = new LocalRuleTocRule();
    rule.chapterList = source.chapterList || '';
    rule.chapterName = source.chapterName || '';
    rule.chapterUrl = source.chapterUrl || '';
    rule.nextTocUrl = source.nextTocUrl || '';
    rule.isVip = source.isVip || '';
    rule.isPay = source.isPay || '';
    rule.isVolume = source.isVolume || '';
    rule.updateTime = source.updateTime || '';
    rule.duration = source.duration || '';
    return rule;
  }

  private static copyContentRule(source: LocalRuleContentRule): LocalRuleContentRule {
    const rule = new LocalRuleContentRule();
    rule.content = source.content || '';
    rule.title = source.title || '';
    rule.audioUrl = source.audioUrl || '';
    rule.nextContentUrl = source.nextContentUrl || '';
    rule.replaceRegex = source.replaceRegex || '';
    rule.sourceRegex = source.sourceRegex || '';
    return rule;
  }

  private static sanitizeHeader(header: string): string {
    const text = header.trim();
    if (text.length === 0) return '';
    try {
      const parsed = JSON.parse(text) as Object;
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) return '';
      const record = parsed as Record<string, Object>;
      const safeHeaders: Record<string, string> = {};
      for (const key of Object.keys(record)) {
        if (!AppBackupService.isSafeHeaderName(key)) continue;
        const value = record[key];
        if (typeof value === 'string' && value.trim().length > 0) {
          safeHeaders[key] = value;
        }
      }
      return Object.keys(safeHeaders).length > 0 ? JSON.stringify(safeHeaders) : '';
    } catch (_error) {
      return '';
    }
  }

  private static isSafeHeaderName(name: string): boolean {
    const normalized = name.trim().toLowerCase();
    return normalized === 'accept' || normalized === 'accept-language' ||
      normalized === 'cache-control' || normalized === 'content-type' ||
      normalized === 'origin' || normalized === 'referer' || normalized === 'user-agent';
  }

  private static validStatus(status: number): number {
    if (status === LocalRuleSourceStatus.READY || status === LocalRuleSourceStatus.FAILED ||
      status === LocalRuleSourceStatus.UNSUPPORTED) return status;
    return LocalRuleSourceStatus.UNCHECKED;
  }

  private static validSourceType(sourceType: number): number {
    if (sourceType === LocalRuleSourceType.AUDIO || sourceType === LocalRuleSourceType.COMIC ||
      sourceType === LocalRuleSourceType.WEB_FILE) return sourceType;
    return LocalRuleSourceType.TEXT;
  }

  private static errorMessage(error: Object): string {
    if (error instanceof Error) return error.message;
    return String(error);
  }
}
