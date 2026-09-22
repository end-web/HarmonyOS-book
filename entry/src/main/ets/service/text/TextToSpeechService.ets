import { SpeechTextHighlighter } from './SpeechTextHighlighter';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { textToSpeech } from '@kit.CoreSpeechKit';
import { audio } from '@kit.AudioKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Book } from '../../model/Book';
import { SpeechPosition, SpeechVoice, TextToSpeechState } from '../../model/TextToSpeechState';
import { StatsService } from '../StatsService';
import { AudioService } from '../AudioService';
import { AVSessionCallbacks, AVSessionService } from '../AVSessionService';
import { BackgroundTaskService } from '../BackgroundTaskService';
import { PlaybackCoordinator } from '../PlaybackCoordinator';
import { PreferenceService } from '../PreferenceService';
import { DataService } from '../DataService';
import { BookSourceService } from '../BookSourceService';
import { OnlineTextContentCache } from './OnlineTextContentCache';
import { OnlineTextPaginator } from './OnlineTextPaginator';
import { SpeechSegment, SpeechTextSegmenter } from './SpeechTextSegmenter';

/** 独立于页面生命周期的离线朗读。停止/换书后所有旧请求均由代次和 requestId 隔离。 */
export class TextToSpeechService {
  private static instance: TextToSpeechService | null = null;
  readonly state: TextToSpeechState = new TextToSpeechState();
  private context: common.UIAbilityContext | null = null;
  private store: preferences.Preferences | null = null;
  private initPromise: Promise<void> | null = null;
  private engine: textToSpeech.TextToSpeechEngine | null = null;
  private downloadedVoices: Set<string> = new Set();
  private enginePerson: number = -1;
  private engineLanguage: string = '';
  private engineChain: Promise<void> = Promise.resolve();
  private book: Book | null = null;
  private segments: SpeechSegment[] = [];
  private segmentIndex: number = 0;
  private generation: number = 0;
  private requestSequence: number = 0;
  private requestId: string = '';
  private watchdog: number = -1;
  private foreground: boolean = true;
  private highlightTimer: number = -1;
  private characterUnitMs: number = 260;
  private utteranceStart: number = 0;
  private sleepTimer: number = -1;
  private sleepDeadline: number = 0;
  private flushChain: Promise<void> = Promise.resolve();
  private lastSaveAt: number = 0;
  private spokenSince: number = 0;
  private pendingListenMs: number = 0;
  private listeners: Set<() => void> = new Set();
  private audioSession: audio.AudioSessionManager | null = null;
  private routing: audio.AudioRoutingManager | null = null;
  private focusChain: Promise<void> = Promise.resolve();
  private prefetchedKey: string = '';
  private prefetchedText: string = '';
  private readonly onDeactivated = (event: audio.AudioSessionDeactivatedEvent): void => {
    hilog.info(0x0000, 'TextToSpeech', 'audio session deactivated reason=%{public}d', event.reason);
    // 系统 TTS 在独立进程出声；本进程空闲会话 60 秒超时不是来电/焦点抢占。
    if (event.reason === audio.AudioSessionDeactivatedReason.DEACTIVATED_TIMEOUT) return;
    if (this.state.playing || this.state.loading) this.pause();
  };
  private readonly onDeviceChange = (event: audio.DeviceChangeAction): void => {
    if (event.type === audio.DeviceChangeType.DISCONNECT && (this.state.playing || this.state.loading)) {
      this.pause();
    }
  };

  static getInstance(): TextToSpeechService {
    if (TextToSpeechService.instance === null) TextToSpeechService.instance = new TextToSpeechService();
    return TextToSpeechService.instance;
  }

  initialize(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    PlaybackCoordinator.stopSpeech = (): Promise<void> => { this.stop(); return this.focusChain; };
    if (this.store !== null) return Promise.resolve();
    if (this.initPromise !== null) return this.initPromise;
    this.initPromise = this.loadSettings(context).finally((): void => { this.initPromise = null; });
    return this.initPromise;
  }

  static async reloadSettings(context: common.Context): Promise<void> {
    const service = TextToSpeechService.instance;
    if (service !== null && service.store !== null) await service.loadSettings(context);
  }

  private async loadSettings(context: common.Context): Promise<void> {
    this.store = await preferences.getPreferences(context, { name: 'text_to_speech' });
    const speed = this.store.getSync('speed', 1);
    const person = this.store.getSync('person', 13);
    const language = this.store.getSync('language', 'zh-CN');
    const follow = this.store.getSync('follow', true);
    this.state.speed = typeof speed === 'number' && Number.isFinite(speed) ? Math.max(0.5, Math.min(2, speed)) : 1;
    this.state.person = typeof person === 'number' && Number.isFinite(person) ? person : 13;
    this.state.language = typeof language === 'string' ? language : 'zh-CN';
    this.state.follow = typeof follow === 'boolean' ? follow : true;
    if (!this.isChineseVoice(this.state.language)) {
      this.state.language = 'zh-CN';
      this.state.person = 13;
      this.saveSettings();
    }
  }

  addListener(listener: () => void): void {
    this.listeners.add(listener);
    if (this.state.playing && this.spokenSince > 0) this.startHighlight();
  }
  removeListener(listener: () => void): void {
    this.listeners.delete(listener);
    if (this.listeners.size === 0) this.stopHighlight();
  }

  private notify(): void {
    this.listeners.forEach((listener: () => void): void => listener());
  }

  private message(resource: Resource): string {
    return this.context?.resourceManager.getStringSync(resource.id) ?? '';
  }

  private report(error: Error): void {
    hilog.warn(0x0000, 'TextToSpeech', '%{public}s', error.message);
  }

  private isChineseVoice(language: string): boolean {
    return language.replace('_', '-').toLowerCase() === 'zh-cn';
  }

  async refreshVoices(): Promise<void> {
    try {
      const query: textToSpeech.VoiceQuery = { requestId: this.nextId(), online: 1 };
      const result = await textToSpeech.listVoices(query);
      const voices: SpeechVoice[] = [];
      for (const item of result) {
        if (item.status === 'EOM' || !this.isChineseVoice(item.language)) continue;
        const voiceId = `${item.language}:${item.person}:${item.style}`;
        const voice = this.state.voices.find((existing: SpeechVoice): boolean => existing.id === voiceId) ?? new SpeechVoice();
        voice.person = item.person;
        voice.language = item.language;
        voice.style = item.style;
        voice.id = `${item.language}:${item.person}:${item.style}`;
        voice.label = item.description || `${item.language} · ${item.person}`;
        voice.installed = this.downloadedVoices.has(voice.id) || item.status === 'INSTALLED' ||
          (item.person === 0 || item.person === 13);
        if (!voices.some((existing: SpeechVoice): boolean => existing.id === voice.id)) voices.push(voice);
      }
      this.state.voices = voices;
      if (voices.length === 0) this.state.error = this.message($r('app.string.tts_no_voices'));
    } catch (error) {
      this.state.error = this.message($r('app.string.tts_engine_error'));
      this.report(error instanceof Error ? error : new Error(String(error)));
    }
  }

  async selectVoice(voice: SpeechVoice): Promise<void> {
    if (this.state.downloadingVoice || !this.isChineseVoice(voice.language)) return;
    this.state.error = '';
    if (!voice.installed) {
      this.state.downloadingVoice = voice.id;
      try {
        await this.downloadVoice(voice);
        this.downloadedVoices.add(voice.id);
        voice.installed = true;
        const current = this.state.voices.find((item: SpeechVoice): boolean => item.id === voice.id);
        if (current) current.installed = true;
      } catch (error) {
        this.state.error = this.message($r('app.string.tts_download_error'));
        this.report(error instanceof Error ? error : new Error(String(error)));
        return;
      } finally {
        this.state.downloadingVoice = '';
      }
    }
    const resume = this.state.playing || this.state.loading;
    this.pause();
    this.state.person = voice.person;
    this.state.language = voice.language;
    this.characterUnitMs = 260;
    this.saveSettings();
    this.releaseEngine();
    if (resume) await this.resume();
  }

  private downloadVoice(voice: SpeechVoice): Promise<void> {
    return new Promise<void>((resolve, reject): void => {
      let finished = false;
      const timer = setTimeout((): void => {
        if (finished) return;
        finished = true;
        reject(new Error('Voice download timed out'));
      }, 180000);
      const params: textToSpeech.VoiceDownload = {
        requestId: this.nextId(), person: voice.person, language: voice.language, style: voice.style
      };
      try {
        textToSpeech.downloadVoice(params, (error, response): void => {
          if (finished) return;
          if (error) {
            finished = true;
            clearTimeout(timer);
            if (error.code === 1002300010) resolve();
            else reject(new Error(error.message));
            return;
          }
          response.on('complete', (): void => {
            if (finished) return;
            finished = true;
            clearTimeout(timer);
            resolve();
          });
          response.on('error', (downloadError): void => {
            if (finished) return;
            finished = true;
            clearTimeout(timer);
            reject(new Error(String(downloadError)));
          });
        });
      } catch (error) {
        finished = true;
        clearTimeout(timer);
        reject(error instanceof Error ? error : new Error(String(error)));
      }
    });
  }

  setSpeed(speed: number): void {
    if (!Number.isFinite(speed)) return;
    const resume = this.state.playing || this.state.loading;
    this.pause();
    this.state.speed = Math.round(Math.max(0.5, Math.min(2, speed)) * 100) / 100;
    this.saveSettings();
    if (resume) this.resume();
  }

  setFollow(follow: boolean): void {
    this.state.follow = follow;
    this.saveSettings();
    this.notify();
  }

  setSleep(minutes: number, chapterEnd: boolean = false): void {
    if (this.sleepTimer !== -1) clearInterval(this.sleepTimer);
    this.sleepTimer = -1;
    this.sleepDeadline = minutes > 0 ? Date.now() + minutes * 60000 : 0;
    this.state.stopAtChapterEnd = chapterEnd;
    this.state.remainingSeconds = Math.max(0, minutes * 60);
    if (minutes > 0) {
      this.sleepTimer = setInterval((): void => {
        this.state.remainingSeconds = Math.max(0, Math.ceil((this.sleepDeadline - Date.now()) / 1000));
        if (this.state.remainingSeconds === 0) {
          this.pause();
          this.setSleep(0);
        }
      }, 1000);
    }
  }

  async start(book: Book, chapterIndex: number, offset: number, restore: boolean = false): Promise<void> {
    const context = this.context;
    if (context === null || book.contentType !== 'text' || book.chapters.length === 0) return;
    this.pause();
    if (this.book !== null && this.book.id !== book.id) { this.setSleep(0); this.pendingListenMs = 0; }
    const ticket = ++this.generation;
    PlaybackCoordinator.speechActive = true;
    this.state.active = true;
    this.state.loading = true;
    this.state.error = '';
    try {
      await this.initialize(context);
      await PreferenceService.applyTocOrder(book);
      if (!this.valid(ticket)) return;
      this.book = book;
      this.state.bookId = book.id;
      this.state.bookTitle = book.title;
      this.state.cover = book.cover;
      this.state.chapterCount = book.chapters.length;
      this.segments = [];
      this.prefetchedKey = '';
      this.prefetchedText = '';
      if (restore) {
        const saved = this.savedPosition(book);
        if (saved !== null) {
          const index = book.chapters.findIndex((chapter): boolean =>
            (chapter.originSourceValue || chapter.source.value) === saved.chapterUrl);
          // 目录重排时只按原章节 URL 恢复，删除的章节回退用户当前阅读位置。
          if (index >= 0) { chapterIndex = index; offset = saved.charOffset; }
        }
      }
      this.state.chapterIndex = Math.max(0, Math.min(chapterIndex, book.chapters.length - 1));
      this.state.charOffset = Math.max(0, offset);
      await this.preparePlayback(ticket);
      if (!this.valid(ticket)) return;
      await this.loadChapter(this.state.chapterIndex, this.state.charOffset, ticket);
    } catch (error) {
      if (this.valid(ticket)) this.fail(error instanceof Error ? error : new Error(String(error)));
    }
  }

  async resume(): Promise<void> {
    if (this.state.playing || this.state.loading || this.book === null) return;
    const ticket = ++this.generation;
    PlaybackCoordinator.speechActive = true;
    this.state.active = true;
    this.state.loading = true;
    this.state.error = '';
    try {
      await this.preparePlayback(ticket);
      if (!this.valid(ticket)) return;
      if (this.segments.length === 0) {
        await this.loadChapter(this.state.chapterIndex, this.state.charOffset, ticket);
      } else {
        this.publishMetadata();
        this.speakNext(ticket);
      }
    } catch (error) {
      if (this.valid(ticket)) this.fail(error instanceof Error ? error : new Error(String(error)));
    }
  }

  pause(): void {
    this.stopHighlight();
    this.recordSpokenTime();
    this.generation++;
    this.requestId = '';
    this.clearWatchdog();
    this.state.playing = false;
    this.state.loading = false;
    try { this.engine?.stop(); } catch (_error) { /* 引擎可能已被系统回收 */ }
    this.savePosition(true);
    this.syncSession();
    if (this.context !== null) BackgroundTaskService.stopSpeech(this.context);
    this.releaseFocus();
    this.notify();
  }

  stop(): void {
    this.pause();
    this.setSleep(0);
    this.releaseEngine();
    AVSessionService.getInstance().endSpeechPlayback();
    PlaybackCoordinator.speechActive = false;
    this.state.active = false;
    this.state.highlightOffset = -1;
    AVSessionService.getInstance().restoreAudioCallbacks();
  }

  async moveChapter(delta: number): Promise<void> {
    if (this.book === null) return;
    const target = this.state.chapterIndex + delta * PreferenceService.chapterStep(this.book);
    if (target < 0 || target >= this.book.chapters.length) return;
    await this.start(this.book, target, 0);
  }

  private valid(ticket: number): boolean {
    return ticket === this.generation && PlaybackCoordinator.speechActive;
  }

  private async preparePlayback(ticket: number): Promise<void> {
    await AudioService.getInstance().suspendForSpeech();
    if (!this.valid(ticket) || this.context === null) return;
    this.installSessionCallbacks();
    await AVSessionService.getInstance().init(this.context);
    if (!this.valid(ticket)) return;
    await this.ensureEngine(ticket);
    if (!this.valid(ticket)) return;
    await this.acquireFocus(ticket);
  }

  private ensureEngine(ticket: number): Promise<void> {
    const task = this.engineChain.catch((): void => {}).then(async (): Promise<void> => {
      if (!this.valid(ticket)) return;
      if (this.engine !== null && this.enginePerson === this.state.person &&
        this.engineLanguage === this.state.language) return;
      this.releaseEngine();
      const person = this.state.person;
      const language = this.state.language;
      const params: textToSpeech.CreateEngineParams = {
        language: language, person: person, online: 1,
        extraParams: { 'isBackStage': true, 'name': 'ListenBookSpeech' }
      };
      const engine = await this.createEngineWithTimeout(params);
      if (!this.valid(ticket)) { engine.shutdown(); return; }
      this.engine = engine;
      this.enginePerson = person;
      this.engineLanguage = language;
      const listener: textToSpeech.SpeakListener = {
        onStart: (id: string, _response: textToSpeech.StartResponse): void => {
          if (id !== this.requestId) return;
          this.spokenSince = Date.now();
          this.startHighlight();
          this.state.loading = false;
          this.state.playing = true;
          if (this.context !== null) BackgroundTaskService.startSpeech(this.context);
          this.syncSession();
          this.notify();
        },
        onComplete: (id: string, response: textToSpeech.CompleteResponse): void => {
          // 合成完成不代表播放结束，只有 type=1 才能推进正文位置。
          if (id !== this.requestId || response.type !== 1) return;
          this.finishHighlight();
          this.recordSpokenTime();
          this.requestId = '';
          this.clearWatchdog();
          this.segmentIndex++;
          this.speakNext(this.generation);
        },
        onStop: (id: string, _response: textToSpeech.StopResponse): void => {
          if (id === this.requestId) this.pause();
        },
        onError: (id: string, code: number, _message: string): void => {
          if (id === this.requestId) this.fail(new Error(`TTS error ${code}`));
        },
        onData: (_id: string, _data: ArrayBuffer, _response: textToSpeech.SynthesisResponse): void => {}
      };
      engine.setListener(listener);
    });
    this.engineChain = task;
    return task;
  }

  private createEngineWithTimeout(params: textToSpeech.CreateEngineParams): Promise<textToSpeech.TextToSpeechEngine> {
    return new Promise<textToSpeech.TextToSpeechEngine>((resolve, reject): void => {
      let finished = false;
      const timer = setTimeout((): void => {
        finished = true;
        reject(new Error('Speech engine initialization timed out'));
      }, 20000);
      textToSpeech.createEngine(params).then((engine: textToSpeech.TextToSpeechEngine): void => {
        if (finished) { engine.shutdown(); return; }
        finished = true;
        clearTimeout(timer);
        resolve(engine);
      }).catch((error: Error): void => {
        if (finished) return;
        finished = true;
        clearTimeout(timer);
        reject(error);
      });
    });
  }

  private releaseEngine(): void {
    const engine = this.engine;
    this.engine = null;
    this.enginePerson = -1;
    if (engine !== null) {
      try { engine.shutdown(); } catch (_error) { /* 已回收 */ }
    }
  }

  private async loadChapter(index: number, offset: number, ticket: number): Promise<void> {
    const book = this.book;
    if (book === null || !this.valid(ticket)) return;
    this.state.loading = true;
    this.state.chapterIndex = index;
    this.state.chapterTitle = book.chapters[index].title;
    this.state.charOffset = offset;
    this.state.contentLength = 0;
    this.state.sentence = '';
    this.state.highlightOffset = -1;
    this.segments = [];
    this.publishMetadata();
    try {
      const content = await this.fetchChapter(book, index);
      if (!this.valid(ticket)) return;
      this.segments = SpeechTextSegmenter.split(content);
      if (this.segments.length === 0) throw new Error('Empty chapter');
      this.state.contentLength = content.length;
      this.segmentIndex = SpeechTextSegmenter.indexAt(this.segments, offset);
      this.speakNext(ticket);
      this.prefetch(book, index + PreferenceService.chapterStep(book), ticket);
    } catch (error) {
      if (this.valid(ticket)) this.fail(error instanceof Error ? error : new Error(String(error)), true);
    }
  }

  private async fetchChapter(book: Book, index: number): Promise<string> {
    const chapter = book.chapters[index];
    const url = chapter.originSourceValue || chapter.source.value;
    const key = OnlineTextContentCache.key(book.sourceUrl, book.bookUrl, url);
    if (key === this.prefetchedKey && this.prefetchedText) return this.prefetchedText;
    const context = this.context;
    if (context !== null) {
      const saved = await OnlineTextContentCache.read(context, key);
      if (saved !== undefined) return saved;
    }
    const value = await BookSourceService.getTextChapterContent(book, url, chapter.title, chapter.variables);
    const content = OnlineTextPaginator.normalizeContent(value.content);
    if (context !== null) await OnlineTextContentCache.write(context, key, content);
    return content;
  }

  private async prefetch(book: Book, index: number, ticket: number): Promise<void> {
    if (index < 0 || index >= book.chapters.length) return;
    try {
      const content = await this.fetchChapter(book, index);
      if (!this.valid(ticket)) return;
      const chapter = book.chapters[index];
      this.prefetchedKey = OnlineTextContentCache.key(book.sourceUrl, book.bookUrl,
        chapter.originSourceValue || chapter.source.value);
      this.prefetchedText = content;
    } catch (_error) { /* 预取失败不影响当前章；到下一章时重试并展示错误。 */ }
  }

  private speakNext(ticket: number): void {
    if (!this.valid(ticket) || this.engine === null || this.book === null) return;
    if (this.sleepDeadline > 0 && Date.now() >= this.sleepDeadline) {
      this.pause(); this.setSleep(0); return;
    }
    if (this.segmentIndex >= this.segments.length) {
      this.state.charOffset = this.state.contentLength;
      this.savePosition(true);
      const next = this.state.chapterIndex + PreferenceService.chapterStep(this.book);
      if (this.state.stopAtChapterEnd || next < 0 || next >= this.book.chapters.length) {
        this.pause(); this.setSleep(0); return;
      }
      this.loadChapter(next, 0, ticket);
      return;
    }
    const segment = this.segments[this.segmentIndex];
    this.state.charOffset = segment.start;
    const rawStart = segment.start;
    // 分段 trim 只改变播报字符串，游标仍映射到原文中的真实位置。
    this.utteranceStart = rawStart + segment.leadingWhitespace;
    this.state.highlightOffset = this.utteranceStart;
    this.state.sentence = segment.text;
    this.requestId = this.nextId();
    this.state.playing = true;
    this.savePosition(false);
    this.notify();
    const params: textToSpeech.SpeakParams = {
      requestId: this.requestId,
      extraParams: { 'queueMode': 0, 'speed': this.state.speed, 'volume': 1, 'pitch': 1,
        'languageContext': this.state.language, 'audioType': 'pcm', 'soundChannel': 3, 'playType': 1, 'isBackStage': true }
    };
    try {
      this.clearWatchdog();
      this.watchdog = setTimeout((): void => {
        if (this.valid(ticket)) this.fail(new Error('Speech callback timed out'));
      }, 150000);
      this.engine.speak(segment.text, params);
    } catch (error) {
      this.fail(error instanceof Error ? error : new Error(String(error)));
    }
  }

  setForeground(foreground: boolean): void {
    this.foreground = foreground;
    if (foreground && this.state.playing) this.startHighlight();
    else this.stopHighlight();
  }

  private startHighlight(): void {
    this.stopHighlight();
    if (!this.foreground || this.listeners.size === 0) return;
    this.advanceHighlight();
    this.highlightTimer = setInterval((): void => this.advanceHighlight(), 80);
  }

  private advanceHighlight(): void {
    if (this.spokenSince <= 0 || !this.requestId) return;
    const offset = this.utteranceStart + SpeechTextHighlighter.offsetAt(this.state.sentence,
      Date.now() - this.spokenSince, this.characterUnitMs / this.state.speed);
    if (offset !== this.state.highlightOffset) {
      this.state.highlightOffset = offset;
      this.notify();
    }
  }

  private finishHighlight(): void {
    this.stopHighlight();
    const weight = SpeechTextHighlighter.totalWeight(this.state.sentence);
    if (weight > 1 && this.spokenSince > 0) {
      const measured = (Date.now() - this.spokenSince) * this.state.speed / weight;
      if (measured >= 80 && measured <= 1000) {
        this.characterUnitMs = Math.max(120, Math.min(650, this.characterUnitMs * 0.35 + measured * 0.65));
      }
    }
  }

  private stopHighlight(): void {
    if (this.highlightTimer !== -1) clearInterval(this.highlightTimer);
    this.highlightTimer = -1;
  }

  private recordSpokenTime(): void {
    if (this.spokenSince <= 0 || this.book === null) return;
    this.pendingListenMs += Math.max(0, Date.now() - this.spokenSince);
    this.spokenSince = 0;
    const seconds = Math.floor(this.pendingListenMs / 1000);
    if (seconds < 1) return;
    this.pendingListenMs -= seconds * 1000;
    const book = this.book;
    StatsService.addListenSeconds(seconds, { bookId: book.id, title: book.title, author: book.author,
      cover: book.cover, sourceUrl: book.sourceUrl, bookUrl: book.bookUrl })
      .catch((error: Error): void => this.report(error));
  }

  private clearWatchdog(): void {
    if (this.watchdog !== -1) clearTimeout(this.watchdog);
    this.watchdog = -1;
  }

  private nextId(): string { return `tts${Date.now()}n${++this.requestSequence}`; }

  private fail(error: Error, content: boolean = false): void {
    this.pause();
    this.releaseEngine();
    this.state.error = this.message(content ? $r('app.string.tts_content_error') : $r('app.string.tts_engine_error'));
    this.report(error);
  }

  private savedPosition(book: Book): SpeechPosition | null {
    const raw = this.store?.getSync(`position_${book.id}`, '');
    if (typeof raw !== 'string' || raw.length === 0) return null;
    try {
      const value: SpeechPosition = JSON.parse(raw);
      if (value === null || value.sourceUrl !== book.sourceUrl || value.bookUrl !== book.bookUrl ||
        typeof value.chapterUrl !== 'string' || !Number.isFinite(value.charOffset) || value.charOffset < 0) return null;
      return value;
    } catch (_error) { return null; }
  }

  hasSavedPosition(book: Book): boolean { return this.savedPosition(book) !== null; }

  private savePosition(force: boolean): void {
    const book = this.book;
    const store = this.store;
    if (store === null || book === null || (!force && Date.now() - this.lastSaveAt < 5000)) return;
    const chapter = book.chapters[this.state.chapterIndex];
    if (chapter === undefined) return;
    const value = new SpeechPosition();
    value.sourceUrl = book.sourceUrl;
    value.bookUrl = book.bookUrl;
    value.chapterUrl = chapter.originSourceValue || chapter.source.value;
    value.chapterIndex = this.state.chapterIndex;
    value.charOffset = this.state.charOffset;
    try {
      store.putSync(`position_${book.id}`, JSON.stringify(value));
      this.lastSaveAt = Date.now();
      this.flush();
    } catch (_error) { this.state.error = this.message($r('app.string.tts_save_error')); }
  }

  private saveSettings(): void {
    if (this.store === null) return;
    try {
    this.store.putSync('speed', this.state.speed);
    this.store.putSync('person', this.state.person);
    this.store.putSync('language', this.state.language);
    this.store.putSync('follow', this.state.follow);
    this.flush();
    } catch (_error) { this.state.error = this.message($r('app.string.tts_save_error')); }
  }

  private flush(): void {
    const store = this.store;
    if (store === null) return;
    this.flushChain = this.flushChain.then((): Promise<void> => store.flush()).catch((error: Error): void => {
      this.state.error = this.message($r('app.string.tts_save_error'));
      this.report(error);
    });
  }

  private installSessionCallbacks(): void {
    const callbacks: AVSessionCallbacks = {
      onPlay: (): void => { this.resume(); }, onPause: (): void => this.pause(),
      onPlayNext: (): void => { this.moveChapter(1); },
      onPlayPrevious: (): void => { this.moveChapter(-1); },
      onFastForward: (_ms: number): void => this.skipSentence(1),
      onRewind: (_ms: number): void => this.skipSentence(-1),
      // TTS 没有精确时长，不把字符数伪装成毫秒或支持虚假的时间拖动。
      onSeek: (_ms: number): void => {}, onSetSpeed: (speed: number): void => this.setSpeed(speed),
      onSetLoopMode: (): void => {}, onCollection: (): void => { this.toggleFavorite(); },
      onCastConnected: (): void => this.pause()
    };
    AVSessionService.getInstance().setSpeechCallbacks(callbacks);
  }

  private skipSentence(delta: number): void {
    if (this.segments.length === 0) return;
    this.pause();
    this.segmentIndex = Math.max(0, Math.min(this.segments.length - 1, this.segmentIndex + delta));
    this.state.charOffset = this.segments[this.segmentIndex].start;
    this.resume();
  }

  private async toggleFavorite(): Promise<void> {
    const book = this.book;
    if (book === null) return;
    try {
      const favorite = await PreferenceService.toggleFavorite(book.id);
      if (favorite) await DataService.upsertCachedBook(book);
      this.syncSession();
    } catch (error) { this.report(error instanceof Error ? error : new Error(String(error))); }
  }

  private publishMetadata(): void {
    if (this.book === null) return;
    AVSessionService.getInstance().updateMetadata(this.book, this.book.chapters[this.state.chapterIndex], true);
  }

  private async syncSession(): Promise<void> {
    if (!PlaybackCoordinator.speechActive || this.book === null) return;
    const ticket = this.generation;
    const favorite = await PreferenceService.isFavorite(this.book.id).catch((): boolean => false);
    if (!this.valid(ticket)) return;
    await AVSessionService.getInstance().updatePlaybackState(this.state.playing, 0, this.state.speed, 0, favorite, true);
  }

  private acquireFocus(ticket: number): Promise<void> {
    const task = this.focusChain.catch((): void => {}).then(async (): Promise<void> => {
      if (!this.valid(ticket)) return;
      if (this.audioSession === null) {
        this.audioSession = audio.getAudioManager().getSessionManager();
        this.audioSession.on('audioSessionDeactivated', this.onDeactivated);
      }
      if (this.routing === null) {
        this.routing = audio.getAudioManager().getRoutingManager();
        this.routing.on('deviceChange', audio.DeviceFlag.OUTPUT_DEVICES_FLAG, this.onDeviceChange);
      }
      await this.audioSession.activateAudioSession({ concurrencyMode: audio.AudioConcurrencyMode.CONCURRENCY_DEFAULT });
    });
    this.focusChain = task;
    return task;
  }

  private releaseFocus(): void {
    this.focusChain = this.focusChain.catch((): void => {}).then(async (): Promise<void> => {
      if (this.audioSession !== null) {
        this.audioSession.off('audioSessionDeactivated', this.onDeactivated);
        await this.audioSession.deactivateAudioSession().catch((): void => {});
        this.audioSession = null;
      }
      if (this.routing !== null) {
        this.routing.off('deviceChange', this.onDeviceChange);
        this.routing = null;
      }
    }).catch((error: Error): void => this.report(error));
  }
}
