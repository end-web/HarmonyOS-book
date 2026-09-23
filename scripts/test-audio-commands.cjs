// Run the real AudioService with simulated platform events, without audio hardware.
// Usage: DEVECO_HOME=<installed IDE> node scripts/test-audio-commands.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME to the installed DevEco Studio directory');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = path.join(__dirname, '../entry/src/main/ets/service/AudioService.ets');
const code = ts.transpileModule(fs.readFileSync(source, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const flush = () => new Promise(resolve => setImmediate(resolve));
const audio = {
  InterruptForceType: { INTERRUPT_FORCE: 0, INTERRUPT_SHARE: 1 },
  InterruptHint: { INTERRUPT_HINT_RESUME: 1, INTERRUPT_HINT_PAUSE: 2, INTERRUPT_HINT_STOP: 3 },
  InterruptMode: { SHARE_MODE: 0, INDEPENDENT_MODE: 1 },
  StreamUsage: { STREAM_USAGE_AUDIOBOOK: 14 },
  AudioStreamDeviceChangeReason: {
    REASON_UNKNOWN: 0, REASON_NEW_DEVICE_AVAILABLE: 1,
    REASON_OLD_DEVICE_UNAVAILABLE: 2, REASON_OVERRODE: 3
  }
};

class Watcher {
  armed = false;
  callback = null;
  arm(callback) { this.armed = true; this.callback = callback; }
  disarm() { this.armed = false; this.callback = null; }
  isArmed() { return this.armed; }
}

async function fixture(initialState = 'paused') {
  const events = new Map();
  const savedPositions = [];
  const player = {
    state: initialState, duration: 180000, currentTime: 42000,
    plays: 0, pauses: 0, seeks: [],
    on(name, callback) { events.set(name, callback); },
    off(name) { events.delete(name); },
    emit(name, value) { events.get(name)?.(value); },
    transition(state) { this.state = state; this.emit('stateChange', state); },
    async play() { this.plays++; this.transition('playing'); },
    async pause() { this.pauses++; this.transition('paused'); },
    seek(position) { this.seeks.push(position); this.currentTime = position; },
    async release() { this.state = 'released'; }
  };
  const state = {
    isPlaying: initialState === 'playing', isLoading: initialState === 'initialized',
    progressMs: 42000, durationMs: 180000, speed: 1,
    currentBook: { id: 'book-1', chapters: [] },
    currentChapter: { id: 'chapter-1', duration: 180, source: { type: 'file', value: 'fixture' } }
  };
  const session = {
    callbacks: null,
    setCallbacks(callbacks) { this.callbacks = callbacks; },
    restoreAudioCallbacks() {}, async updateMetadata() {},
    async init() {}, async destroy() {}, async updateMetadataDuration() {}
  };
  const playbackStore = { setPlaying() {}, update() {} };
  const cacheCalls = [];
  const mediaSources = [];
  const platformCompat = { supports: () => true };
  const cache = {
    suspendPreload() { cacheCalls.push('suspend'); },
    resumePreload() { cacheCalls.push('resume'); },
    ensureFileCached() { cacheCalls.push('current'); },
    preloadAudioChapters() { cacheCalls.push('next'); }
  };
  const coordinatorModule = { exports: {} };
  const coordinatorCode = ts.transpileModule(fs.readFileSync(
    path.join(path.dirname(source), 'PlaybackCoordinator.ets'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  vm.runInNewContext(coordinatorCode, { module: coordinatorModule, exports: coordinatorModule.exports });
  const prefModule = { exports: {} };
  const prefCode = ts.transpileModule(fs.readFileSync(
    path.join(path.dirname(source), 'PreferenceService.ets'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  vm.runInNewContext(prefCode, { module: prefModule, exports: prefModule.exports,
    require: () => ({ ConfigurationConstant: { ColorMode: { COLOR_MODE_NOT_SET: -1 } } }) });
  const preference = prefModule.exports.PreferenceService;
  const preferenceValues = new Map();
  preference.ensureStore = async () => ({
    get: async (key, fallback) => preferenceValues.get(key) ?? fallback,
    put: async (key, value) => preferenceValues.set(key, value),
    delete: async key => preferenceValues.delete(key), flush: async () => {}
  });
  const modules = {
    './LiveAudioService': { LiveAudioService: { isLive: async () => false } },
    './ChapterCacheService': { ChapterCacheService: { getInstance: () => cache } },
    './PlaybackCoordinator': coordinatorModule.exports,
    '@kit.MediaKit': { media: { createAVPlayer: async () => player, SeekMode: { SEEK_PREV_SYNC: 0 },
      createMediaSourceWithUrl(url, headers) {
        const source = { url, headers, offlineCache: false,
          enableOfflineCache(enable) { this.offlineCache = enable; } };
        mediaSources.push(source);
        return source;
      }
    } },
    '@kit.AudioKit': { audio },
    '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn() {}, error() {} } },
    '@kit.BasicServicesKit': { emitter: { emit() {} } },
    '@kit.AVSessionKit': { avSession: {} },
    '@kit.CoreFileKit': { fileIo: {} },
    '../utils/PlatformCompat': { PlatformCompat: platformCompat },
    '../model/PlayerState': { SleepMode: { Off: 0, Chapters: 2 }, PlayMode: { Sequence: 0, SingleLoop: 1, ListLoop: 2 } },
    './ExternalMediaWatcher': { ExternalMediaWatcher: Watcher },
    './AVSessionService': { AVSessionService: { getInstance: () => session } },
    './PlaybackStore': { PlaybackStore: { getInstance: () => playbackStore } },
    './BackgroundTaskService': { BackgroundTaskService: { async start() {}, async stop() {}, isRunning() { return true; } } },
    './DataService': { DataService: { async upsertCachedBook() {},
      resolveChapterIndex: (book, id) => book.chapters.findIndex(ch => ch.id === id) } },
    './PreferenceService': { PreferenceService: preference },
    './WidgetUpdater': { WidgetUpdater: { async optimisticSetPlaying() {} } }
  };
  const module = { exports: {} };
  const downloadPolicy = { exports: {} };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(
    path.join(path.dirname(source), 'DownloadPolicy.ets'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { module: downloadPolicy, exports: downloadPolicy.exports });
  modules['./DownloadPolicy'] = downloadPolicy.exports;
  vm.runInNewContext(code, {
    module, exports: module.exports, console, setTimeout, clearTimeout, setInterval, clearInterval,
    require(name) {
      if (modules[name]) return modules[name];
      // Unused business dependencies remain unloaded; unexpected calls fail normally.
      if (name.startsWith('./') || name.startsWith('../model/')) return {};
      throw new Error(`Unexpected platform dependency: ${name}`);
    }
  }, { filename: source });
  const service = module.exports.AudioService.getInstance();
  service.state = state;
  service.context = {};
  service.persistHistory = async () => { savedPositions.push(state.progressMs); };
  service.syncPlaybackState = () => {};
  service.syncPlaybackStateNow = async () => {};
  service.startTick = () => {};
  service.stopTick = () => {};
  service.initAVSession();
  await service.ensurePlayer();
  return { service, player, state, session, savedPositions, events, preference, cacheCalls,
    mediaSources, platformCompat };
}

let passed = 0;
async function check(name, test) {
  await test();
  console.log(`PASS ${name}`);
  passed++;
}

(async () => {
  await check('HLS and indexed containers bypass offline cache; ordinary audio keeps caching', async () => {
    const f = await fixture();
    const loaded = [];
    f.player.setMediaSource = async source => { loaded.push(source); };
    const headers = { 'User-Agent': 'radio-fixture', Referer: 'https://radio.test/' };
    for (const live of [true, false]) {
      f.service.liveSource = live;
      assert.equal(await f.service.applySource(f.player,
        { type: 'url', value: 'https://radio.test/stream.m3u8?session=fixture' }, headers), true);
      assert.equal(loaded.at(-1).offlineCache, false);
      assert.equal(loaded.at(-1).headers, headers);
    }
    f.service.liveSource = true;
    await f.service.applySource(f.player, { type: 'url', value: 'https://radio.test/live' });
    assert.equal(loaded.at(-1).offlineCache, false);
    f.service.liveSource = false;
    for (const suffix of ['chapter.m4a', 'chapter.M4A?token=test', 'chapter.m4b', 'chapter.mp4', 'chapter.mov']) {
      await f.service.applySource(f.player, { type: 'url', value: 'https://audio.test/' + suffix }, headers);
      assert.equal(loaded.at(-1).offlineCache, false, suffix);
      assert.equal(loaded.at(-1).headers, headers);
    }
    await f.service.applySource(f.player, { type: 'url', value: 'https://radio.test/chapter.mp3' });
    assert.equal(loaded.at(-1).offlineCache, true);
    f.platformCompat.supports = () => false;
    await f.service.applySource(f.player, { type: 'url', value: 'https://radio.test/chapter.mp3' });
    assert.equal(loaded.at(-1).offlineCache, false);
  });
  await check('HLS rolling-window duration remains live and normal audio replaces stalled radio', async () => {
    const f = await fixture('initialized');
    f.service.liveSource = true;
    f.player.duration = 60000;
    f.state.currentChapter.source = { type: 'url', value: 'https://radio.test/live.m3u8' };
    f.player.transition('prepared');
    assert.equal(f.state.isLive, true);
    assert.equal(f.state.durationMs, 0);
    const oldStateCallback = f.events.get('stateChange');
    f.player.reset = () => new Promise(() => {});
    f.player.release = () => new Promise(() => {});
    const nextPlayer = { state: 'idle' };
    f.service.ensurePlayer = async () => { f.service.player = nextPlayer; return nextPlayer; };
    f.service.isFastSwitchPath = () => true;
    f.service.resolveAudioUrl = async () => ({ success: true, headers: {} });
    f.service.syncCastMediaSource = () => {};
    f.service.applySource = async () => true;
    const chapter = { id: 'other-chapter', source: { type: 'file', value: '/audio.mp3' } };
    const book = { id: 'other-book', chapters: [chapter] };
    await Promise.race([f.service.doPlayChapter(book, chapter, 0),
      new Promise((_, reject) => setTimeout(() => reject(new Error('radio blocked switch')), 1000))]);
    assert.equal(f.state.currentBook.id, 'other-book');
    assert.equal(f.state.isLive, false);
    oldStateCallback('prepared', 1);
    assert.equal(f.state.isLive, false);
    assert.equal(f.state.currentBook.id, 'other-book');
  });
  await check('live recovery obeys generation and pause and never seeks old stream', async () => {
    const f = await fixture('playing');
    f.state.isLive = true;
    f.service.liveSource = true;
    let reconnects = 0;
    f.service.doPlayChapter = async (_book, _chapter, position) => {
      assert.equal(position, 0); reconnects++;
    };
    f.service.recoverLiveBuffer(f.player, f.service.playGen + 1);
    f.service.pauseRequested = true;
    f.service.recoverLiveBuffer(f.player, f.service.playGen);
    assert.equal(reconnects, 0);
    f.service.pauseRequested = false;
    f.service.recoverLiveBuffer(f.player, f.service.playGen);
    assert.equal(reconnects, 1);
    assert.equal(f.service.player, null);
    assert.deepEqual(f.player.seeks, []);
  });
  await check('live streams start without historical seek, speed or preloading', async () => {
    const f = await fixture('initialized');
    f.state.currentChapter.source = { type: 'url', value: 'https://radio.test/live.m3u8' };
    f.state.currentBook.chapters = [f.state.currentChapter];
    f.player.duration = -1;
    f.state.speed = 1.5;
    f.service.pendingSeek = 80000;
    f.service.resumeTargetMs = 80000;
    f.player.transition('prepared');
    assert.equal(f.player.plays, 1);
    assert.equal(f.state.isLive, true);
    assert.equal(f.state.durationMs, 0);
    assert.equal(f.service.resumeTargetMs, 0);
    await f.service.seek(10000);
    await f.service.seekAndPlaySameChapter(20000);
    await new Promise(resolve => setTimeout(resolve, 10));
    assert.deepEqual(f.player.seeks, []);
    assert.deepEqual(f.cacheCalls, []);
  });
  await check('preload starts after playing and obsolete tasks do not start', async () => {
    const f = await fixture('initialized');
    f.state.currentBook.chapters = [f.state.currentChapter];
    assert.deepEqual(f.cacheCalls, []);
    f.player.transition('prepared');
    assert.equal(f.player.plays, 1);
    assert.deepEqual(f.cacheCalls, []);
    await new Promise(resolve => setTimeout(resolve, 10));
    assert.deepEqual(f.cacheCalls, ['resume', 'next']);
    f.cacheCalls.length = 0;
    f.service.triggerPreload(f.state.currentBook, f.state.currentChapter);
    f.service.playGen++;
    await new Promise(resolve => setTimeout(resolve, 10));
    assert.deepEqual(f.cacheCalls, []);
  });
  await check('manual play recovers an errored player at the saved position', async () => {
    const f = await fixture('error');
    let resumedAt = -1;
    f.service.resumeFromState = async () => { resumedAt = f.state.progressMs; };
    await f.service.play();
    assert.equal(resumedAt, 42000);
  });
  await check('resolved URL errors retry at the interrupted position', async () => {
    const f = await fixture('playing');
    f.state.currentChapter.source = { type: 'url', value: 'https://example.invalid/audio' };
    f.state.currentChapter.originSourceValue = 'https://example.invalid/chapter';
    let retry = null;
    f.service.playChapterAndSeek = async (_book, _chapter, position, automatic) => { retry = { position, automatic }; };
    f.player.state = 'error';
    f.player.emit('error', { code: 5400103, message: 'simulated failure' });
    await flush();
    assert.deepEqual(retry, { position: 42000, automatic: true });
  });
  await check('explicit pause prevents automatic URL-error recovery', async () => {
    const f = await fixture('playing');
    f.state.currentChapter.source = { type: 'url', value: 'https://example.invalid/audio' };
    f.state.currentChapter.originSourceValue = 'https://example.invalid/chapter';
    let retries = 0;
    f.service.playChapterAndSeek = async () => { retries++; };
    await f.service.pause();
    f.player.state = 'error';
    f.player.emit('error', { code: 5400103, message: 'simulated failure' });
    await flush();
    assert.equal(retries, 0);
    assert.equal(f.state.isPlaying, false);
  });
  await check('session play/pause are idempotent and preserve the current position', async () => {
    const f = await fixture();
    f.session.callbacks.onPlay();
    await flush();
    f.session.callbacks.onPlay();
    await flush();
    assert.equal(f.player.plays, 1);
    assert.equal(f.player.pauses, 0);
    assert.equal(f.state.progressMs, 42000);
    assert.equal(f.player.seeks.length, 0);
    f.session.callbacks.onPause();
    f.session.callbacks.onPause();
    await flush();
    assert.equal(f.player.pauses, 1);
    assert.equal(f.state.isPlaying, false);
  });
  await check('headset removal pauses; reconnection waits for a session play command', async () => {
    const f = await fixture('playing');
    f.player.emit('audioOutputDeviceChangeWithInfo', { changeReason: 2, devices: [] });
    await flush();
    assert.equal(f.player.state, 'paused');
    assert.ok(f.savedPositions.includes(42000));
    f.player.emit('audioOutputDeviceChangeWithInfo', { changeReason: 1, devices: [] });
    await flush();
    assert.equal(f.player.plays, 0);
    f.session.callbacks.onPlay();
    await flush();
    assert.equal(f.player.state, 'playing');
    assert.equal(f.player.currentTime, 42000);
  });
  await check('new, unknown and user-selected output routes do not pause playback', async () => {
    const f = await fixture('playing');
    for (const changeReason of [0, 1, 3]) {
      f.player.emit('audioOutputDeviceChangeWithInfo', { changeReason, devices: [] });
    }
    await flush();
    assert.equal(f.player.pauses, 0);
  });
  await check('pause during preparation blocks autoplay and resumes at the pending seek', async () => {
    const f = await fixture('initialized');
    f.service.pendingSeek = 42000;
    f.player.emit('audioOutputDeviceChangeWithInfo', { changeReason: 2, devices: [] });
    f.player.transition('prepared');
    await flush();
    assert.equal(f.player.plays, 0);
    assert.equal(f.state.isPlaying, false);
    assert.equal(f.state.isLoading, false);
    f.session.callbacks.onPlay();
    await flush();
    assert.equal(f.player.plays, 1);
    assert.equal(f.player.currentTime, 42000);
  });
  await check('a later pause wins over an already scheduled play', async () => {
    const f = await fixture();
    const play = f.service.play();
    await f.service.pause();
    await play;
    assert.equal(f.player.plays, 0);
    assert.equal(f.state.isPlaying, false);
  });
  await check('session pause cancels external-media and delayed focus recovery', async () => {
    const f = await fixture();
    f.service.pausedByFocus = true;
    f.service.pausedByExternalMedia = true;
    const watcher = f.service.externalWatcher;
    watcher.arm(() => f.service.resumeAfterExternalMedia());
    const staleCallback = watcher.callback;
    f.session.callbacks.onPause();
    f.player.emit('audioInterrupt', { forceType: 1, hintType: 1 });
    staleCallback();
    await flush();
    assert.equal(watcher.isArmed(), false);
    assert.equal(f.player.plays, 0);
  });
  await check('focus recovery still resumes when no explicit pause was requested', async () => {
    const f = await fixture();
    f.player.emit('audioInterrupt', { forceType: 0, hintType: 2 });
    f.player.emit('audioInterrupt', { forceType: 1, hintType: 1 });
    await flush();
    assert.equal(f.player.plays, 1);
  });
  await check('a late playing event is paused again after headset removal', async () => {
    const f = await fixture('initialized');
    await f.service.pause();
    f.player.transition('playing');
    await flush();
    assert.equal(f.player.state, 'paused');
    assert.equal(f.state.isPlaying, false);
  });
  await check('release unregisters the output device listener', async () => {
    const f = await fixture();
    await f.service.release();
    assert.equal(f.events.has('audioOutputDeviceChangeWithInfo'), false);
  });
  await check('saving intro 10s at 2s immediately seeks, including paused playback', async () => {
    for (const mode of ['playing', 'paused']) {
      const f = await fixture(mode);
      f.state.progressMs = f.player.currentTime = 2000;
      f.service.applySkipConfigNow('book-1', 10, 0);
      assert.deepEqual(f.player.seeks, [10000]);
      assert.equal(f.state.progressMs, 10000);
      assert.equal(f.player.state, mode);
    }
  });
  await check('saving intro 10s at 11s never rewinds and other books are untouched', async () => {
    const f = await fixture('playing');
    f.state.progressMs = f.player.currentTime = 11000;
    f.service.applySkipConfigNow('book-1', 10, 0);
    f.service.applySkipConfigNow('other-book', 30, 0);
    assert.deepEqual(f.player.seeks, []);
    assert.equal(f.state.progressMs, 11000);
    assert.equal(f.state.currentBook.skipIntro, 10);
  });
  await check('saving outro inside the current tail triggers chapter completion immediately', async () => {
    const f = await fixture('playing');
    f.state.progressMs = f.player.currentTime = 175000;
    let completed = 0;
    f.service.handleChapterEnd = () => completed++;
    f.service.applySkipConfigNow('book-1', 0, 10);
    assert.equal(completed, 1);
    assert.deepEqual(f.player.seeks, []);
  });
  await check('intro saved during loading updates the pending seek', async () => {
    const f = await fixture('initialized');
    f.state.progressMs = 2000;
    f.service.applySkipConfigNow('book-1', 10, 0);
    assert.equal(f.service.pendingSeek, 10000);
    assert.deepEqual(f.player.seeks, []);
  });
  await check('book order persists independently and all playback directions follow it', async () => {
    const f = await fixture('playing');
    const book = f.state.currentBook;
    book.chapters = ['a', 'b', 'c'].map(id => ({ id, title: id }));
    f.state.currentChapter = book.chapters[1];
    await f.preference.saveTocOrder(book.id, true);
    f.preference.tocOrderMemo.clear();
    await f.preference.applyTocOrder(book);
    assert.equal(book.chaptersDescending, true);
    assert.equal(f.preference.orderedChapters(book).map(ch => ch.id).join(','), 'c,b,a');
    assert.equal(book.chapters.map(ch => ch.id).join(','), 'a,b,c');
    assert.equal(f.preference.chapterStep({ id: 'other' }), 1);
    const played = [];
    f.service.playChapter = async (_book, chapter) => played.push(chapter.id);
    f.service.playChapterFromSavedProgress = f.service.playChapter;
    await f.service.playNext();
    await f.service.playPrevious();
    f.service.autoPlayNext();
    assert.deepEqual(played, ['a', 'c', 'a']);
    assert.equal(f.service.getAvailableSleepChapters(), 2);
    assert.equal(f.service.setSleepChapters(2), true);
    assert.equal(f.state.sleepTargetTitle, 'a');
    f.state.sleepMode = 0;
    f.state.currentChapter = book.chapters[0];
    await f.service.playNext();
    assert.equal(played.length, 3);
    f.state.playMode = 2;
    await f.service.playNext();
    assert.equal(played.at(-1), 'c');
    await f.preference.saveTocOrder(book.id, false);
    assert.equal(f.preference.chapterStep(book), 1);
    await f.service.playNext();
    assert.equal(played.at(-1), 'b');
  });
  console.log(`${passed} audio command checks passed`);
})().catch(error => { console.error(error); process.exitCode = 1; });
