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
  const playbackStore = { setPlaying() {} };
  const coordinatorModule = { exports: {} };
  const coordinatorCode = ts.transpileModule(fs.readFileSync(
    path.join(path.dirname(source), 'PlaybackCoordinator.ets'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  vm.runInNewContext(coordinatorCode, { module: coordinatorModule, exports: coordinatorModule.exports });
  const modules = {
    './PlaybackCoordinator': coordinatorModule.exports,
    '@kit.MediaKit': { media: { createAVPlayer: async () => player, SeekMode: { SEEK_PREV_SYNC: 0 } } },
    '@kit.AudioKit': { audio },
    '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn() {}, error() {} } },
    '@kit.BasicServicesKit': { emitter: { emit() {} } },
    '@kit.AVSessionKit': { avSession: {} },
    '@kit.CoreFileKit': { fileIo: {} },
    '../utils/PlatformCompat': { PlatformCompat: {} },
    '../model/PlayerState': { SleepMode: { Off: 0, Chapters: 2 } },
    './ExternalMediaWatcher': { ExternalMediaWatcher: Watcher },
    './AVSessionService': { AVSessionService: { getInstance: () => session } },
    './PlaybackStore': { PlaybackStore: { getInstance: () => playbackStore } },
    './BackgroundTaskService': { BackgroundTaskService: { async start() {}, async stop() {} } },
    './DataService': { DataService: { async upsertCachedBook() {} } },
    './WidgetUpdater': { WidgetUpdater: { async optimisticSetPlaying() {} } }
  };
  const module = { exports: {} };
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
  return { service, player, state, session, savedPositions, events };
}

let passed = 0;
async function check(name, test) {
  await test();
  console.log(`PASS ${name}`);
  passed++;
}

(async () => {
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
  console.log(`${passed} audio command checks passed`);
})().catch(error => { console.error(error); process.exitCode = 1; });
