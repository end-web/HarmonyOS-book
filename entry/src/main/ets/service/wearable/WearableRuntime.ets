import { common } from '@kit.AbilityKit';
import { AppStorageV2 } from '@kit.ArkUI';
import { PlayerState, PLAYER_STATE_KEY } from '../../model/PlayerState';
import { AudioService } from '../AudioService';
import { AVSessionService } from '../AVSessionService';
import { AuthService } from '../AuthService';
import { ChapterCacheService } from '../ChapterCacheService';
import { DataService } from '../DataService';
import { DownloadService } from '../DownloadService';
import { PreferenceService } from '../PreferenceService';
import { StatsService } from '../StatsService';
import { LocalRuleSourceRepository } from '../rulesource/LocalRuleSourceRepository';
import { LocalRuleTlsTrustStore } from '../rulesource/LocalRuleTlsTrustStore';
import { configureArkWebSecurity } from '../builtin/ArkWebSecurityConfig';

/** 手表只初始化独立听书所需服务，不进入手机阅读器、卡片和自动备份启动链。 */
@ObservedV2
export class WearableRuntime {
  private static singleton: WearableRuntime | null = null;
  static get instance(): WearableRuntime {
    if (!WearableRuntime.singleton) WearableRuntime.singleton = new WearableRuntime();
    return WearableRuntime.singleton;
  }

  @Trace ready: boolean = false;
  @Trace failed: boolean = false;
  private task: Promise<void> | null = null;
  private context: common.UIAbilityContext | null = null;
  private active: boolean = false;

  getContext(): common.UIAbilityContext | null {
    return this.context;
  }

  initialize(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    if (this.task) return this.task;
    this.failed = false;
    this.task = this.initializeCore(context).then((): void => {
      this.ready = true;
    }).catch((error: Error): void => {
      this.failed = true;
      this.task = null;
      console.error('[WearableRuntime] initialization failed: ' + error.message);
    });
    return this.task;
  }

  private async initializeCore(context: common.UIAbilityContext): Promise<void> {
    configureArkWebSecurity();
    DataService.setContext(context);
    ChapterCacheService.getInstance().setContext(context);
    DownloadService.getInstance().setContext(context);
    await PreferenceService.init(context);
    await LocalRuleTlsTrustStore.init(context);
    await LocalRuleSourceRepository.init(context);
    await DownloadService.getInstance().init(context);
    await StatsService.init(context);
    // 手表不进行手机默认的连续章节预加载，主动下载仍使用原下载队列。
    ChapterCacheService.getInstance().setPreloadCount(0);
    AVSessionService.getInstance().init(context);
    const player = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;
    AudioService.getInstance().bind(player, context);
    try {
      const last = await PreferenceService.getLastPlayed();
      if (last) {
        const book = await DataService.getBookById(context, last.bookId);
        if (book && book.contentType !== 'text') {
          const index = DataService.resolveChapterIndex(book, last.chapterId, last.chapterTitle);
          if (index >= 0) {
            await PreferenceService.applySkipConfig(book);
            await PreferenceService.applyTocOrder(book);
            player.currentBook = book;
            player.currentChapter = book.chapters[index];
            player.progressMs = last.progressMs;
            player.savedDurationMs = last.durationMs ?? 0;
          }
        }
      }
    } finally {
      AudioService.getInstance().markReady();
    }
    // 在 ready 之后恢复队列；账号服务不可用不阻塞本地播放。
    DownloadService.getInstance().restoreDownloads().catch((error: Error): void => {
      console.warn('[WearableRuntime] download recovery failed: ' + error.message);
    });
  }

  async foreground(context: common.UIAbilityContext): Promise<void> {
    this.active = true;
    await this.initialize(context);
    if (!this.ready || !this.active) return;
    AudioService.getInstance().setForeground(true);
    AuthService.instance.restoreSharedAccount(context).catch((): void => {});
    await AudioService.getInstance().ensureHealthy();
  }

  async background(): Promise<void> {
    this.active = false;
    if (!this.ready) return;
    AudioService.getInstance().setForeground(false);
    await AudioService.getInstance().flushHistory();
    await DownloadService.getInstance().onAppBackground();
    await StatsService.flush();
  }

  async destroy(): Promise<void> {
    this.active = false;
    if (this.task) await this.task;
    if (this.ready) {
      await AudioService.getInstance().flushHistory();
      await AudioService.getInstance().release();
      await StatsService.flush();
    }
    this.ready = false;
    this.task = null;
  }
}
