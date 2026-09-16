// Execute the real ArkTS service with deterministic speech, storage and audio mocks.
// DEVECO_HOME must point to an installed DevEco Studio. No device state is modified.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
function load(relative, dependencies = {}, globals = {}) {
  const file = path.join(root, relative);
  const source = fs.readFileSync(file, 'utf8').replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
  const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  const module = { exports: {} };
  vm.runInNewContext(code, { module, exports: module.exports, console, Date, Map, Set, Promise, Error,
    $r: id => ({ id }), ...globals, require(name) {
      if (!(name in dependencies)) throw new Error(`Unexpected dependency ${name}`);
      return dependencies[name];
    } }, { filename: file });
  return module.exports;
}
const { SpeechTextSegmenter } = load('service/text/SpeechTextSegmenter.ets');
const model = load('model/TextToSpeechState.ets');
const { SpeechTextHighlighter } = load('service/text/SpeechTextHighlighter.ets');
const settle = async () => { for (let i = 0; i < 45; i++) await Promise.resolve(); };
const book = (id = 'book', texts = ['第一句。第二句！', '第三句。']) => ({ id, contentType: 'text', title: id,
  sourceUrl: 'https://source.example', bookUrl: `https://book.example/${id}`, author: 'author', cover: '',
  chapters: texts.map((text, index) => ({ id: String(index), title: `章节${index}`, source: { value: `${id}/${index}`, type: 'url' }, text })) });
function harness(memory = new Map()) {
  const engines = [], spoken = [], timers = new Map(), cached = new Map(), stats = [];
  let id = 0, failContent = false, createDeferred = null, focusCallback = null, deviceCallback = null;
  const coordinator = load('service/PlaybackCoordinator.ets');
  const session = { callbacks: null, paused: false, setSpeechCallbacks(cbs) { this.callbacks = cbs; },
    restoreAudioCallbacks() {}, endSpeechPlayback() { this.paused = true; },
    init: async () => {}, updateMetadata: async () => {}, updatePlaybackState: async () => {} };
  const audioSession = { on: (_event, cb) => { focusCallback = cb; }, off: () => { focusCallback = null; },
    activateAudioSession: async () => {}, deactivateAudioSession: async () => {} };
  const routing = { on: (_event, _flag, cb) => { deviceCallback = cb; }, off: () => { deviceCallback = null; } };
  const tts = { listVoices: async () => [{ person: 13, language: 'zh-CN', style: 'interaction-broadcast', description: 'female', status: 'INSTALLED' }],
    createEngine: async () => {
      if (createDeferred) await createDeferred;
      const engine = { listener: null, closed: false, setListener(listener) { this.listener = listener; },
        stop() {}, shutdown() { this.closed = true; }, speak(text, params) {
          spoken.push({ engine, text, id: params.requestId, speed: params.extraParams.speed });
          this.listener.onStart(params.requestId, {});
        } };
      engines.push(engine); return engine;
    } };
  const dependencies = {
    '@kit.ArkData': { preferences: { getPreferences: async () => ({ getSync: (key, fallback) => memory.get(key) ?? fallback,
      putSync: (key, value) => memory.set(key, value), flush: async () => {} }) } },
    '@kit.CoreSpeechKit': { textToSpeech: tts },
    '@kit.AudioKit': { audio: { getAudioManager: () => ({ getSessionManager: () => audioSession, getRoutingManager: () => routing }),
      AudioSessionDeactivatedReason: { DEACTIVATED_TIMEOUT: 1 }, DeviceFlag: { OUTPUT_DEVICES_FLAG: 1 }, DeviceChangeType: { DISCONNECT: 1 }, AudioConcurrencyMode: { CONCURRENCY_DEFAULT: 0 } } },
    '@kit.PerformanceAnalysisKit': { hilog: { warn() {}, info() {} } },
    '../../model/TextToSpeechState': model,
    '../AudioService': { AudioService: { getInstance: () => ({ suspendForSpeech: async () => {} }) } },
    '../AVSessionService': { AVSessionService: { getInstance: () => session } },
    '../BackgroundTaskService': { BackgroundTaskService: { startSpeech: async () => {}, stopSpeech: async () => {} } },
    '../PlaybackCoordinator': coordinator,
    '../PreferenceService': { PreferenceService: { isFavorite: async () => false, toggleFavorite: async () => true } },
    '../StatsService': { StatsService: { addListenSeconds: async (seconds, value) => stats.push([seconds, value]) } },
    '../DataService': { DataService: { upsertCachedBook: async () => {} } },
    '../BookSourceService': { BookSourceService: { getTextChapterContent: async (value, url) => {
      if (failContent) throw new Error('network');
      return { content: value.chapters.find(ch => ch.source.value === url).text };
    } } },
    './OnlineTextContentCache': { OnlineTextContentCache: { key: (...parts) => parts.join('|'),
      read: async (_ctx, key) => cached.get(key), write: async (_ctx, key, text) => cached.set(key, text) } },
    './OnlineTextPaginator': { OnlineTextPaginator: { normalizeContent: value => value } },
    './SpeechTextHighlighter': { SpeechTextHighlighter },
    './SpeechTextSegmenter': { SpeechTextSegmenter }
  };
  const { TextToSpeechService } = load('service/text/TextToSpeechService.ets', dependencies, {
    setTimeout: (callback, delay) => { const key = ++id; timers.set(key, { callback, delay }); return key; },
    clearTimeout: key => timers.delete(key), setInterval: (callback, delay) => { const key = ++id; timers.set(key, { callback, delay }); return key; },
    clearInterval: key => timers.delete(key)
  });
  const service = TextToSpeechService.getInstance();
  const context = { resourceManager: { getStringSync: key => key } };
  return { service, tts, memory, spoken, engines, timers, session, coordinator: coordinator.PlaybackCoordinator,
    init: () => service.initialize(context), failContent: value => { failContent = value; },
    deferEngine: value => { createDeferred = value; }, focus: (reason = 0) => focusCallback?.({ reason }),
    unplug: () => deviceCallback?.({ type: 1 }),
    complete(type = 1, request = spoken.at(-1)) { request.engine.listener.onComplete(request.id, { type }); } };
}
let passed = 0;
async function check(name, action) { await action(); console.log(`PASS ${name}`); passed++; }
(async () => {
  await check('默认中文女声兼容语言和编号别名，内置音色无需下载即显示已选择', async () => {
    const h = harness(); await h.init();
    h.tts.listVoices = async () => [{ person: 0, language: 'zh_CN', style: 'interaction-broadcast', status: 'NOT_INSTALLED' },
      { person: 21, language: 'zh-CN', style: 'interaction-broadcast', status: 'INSTALLED' }];
    await h.service.refreshVoices();
    const [female, male] = h.service.state.voices;
    assert.equal(female.installed, true);
    assert.equal(h.service.state.isVoiceSelected(female), true);
    assert.equal(h.service.state.isVoiceSelected(male), false);
    await h.service.selectVoice(male);
    assert.equal(h.service.state.isVoiceSelected(female), false);
    assert.equal(h.service.state.isVoiceSelected(male), true);
    h.service.state.person = 0;
    h.service.state.language = 'zh_CN';
    assert.equal(h.service.state.isVoiceSelected({ person: 13, language: 'zh-CN' }), true);
    assert.equal(h.service.state.isVoiceSelected({ person: 13, language: 'en-US' }), false);
  });
  await check('只展示中文音色，历史英文选择恢复默认中文且不允许重新选英文', async () => {
    const h = harness(new Map([['language', 'en-US'], ['person', 8]]));
    await h.init();
    assert.equal(h.service.state.language, 'zh-CN');
    assert.equal(h.service.state.person, 13);
    const english = { id: 'en-US:8:interaction-broadcast', person: 8, language: 'en-US', style: 'interaction-broadcast', installed: true };
    h.tts.listVoices = async () => [english, { person: 13, language: 'zh_CN', style: 'interaction-broadcast', status: 'INSTALLED' }];
    await h.service.refreshVoices();
    assert.equal(h.service.state.voices.length, 1);
    assert.equal(h.service.state.voices[0].language, 'zh_CN');
    await h.service.selectVoice(english);
    assert.equal(h.service.state.person, 13);
    await settle();
    assert.equal(h.memory.get('language'), 'zh-CN');
  });
  await check('下载成功立即更新音色行，旧查询结果不能回退或重复下载', async () => {
    const h = harness(); await h.init();
    const info = { person: 21, language: 'zh-CN', style: 'interaction-broadcast', description: 'male', status: 'NOT_INSTALLED' };
    h.tts.listVoices = async () => [info];
    let downloads = 0;
    h.tts.downloadVoice = (_params, callback) => {
      downloads++;
      callback(null, { on(event, handler) { if (event === 'complete') handler(); } });
    };
    await h.service.refreshVoices();
    const row = h.service.state.voices[0];
    await h.service.selectVoice(row);
    assert.equal(row.installed, true);
    assert.equal(h.service.state.person, 21);
    await h.service.refreshVoices();
    assert.equal(h.service.state.voices[0], row);
    assert.equal(row.installed, true);
    await h.service.selectVoice(row);
    assert.equal(downloads, 1);
  });
  await check('已有行响应系统安装状态更新，下载失败不误标记已安装', async () => {
    const h = harness(); await h.init();
    const info = { person: 21, language: 'zh-CN', style: 'interaction-broadcast', description: 'male', status: 'NOT_INSTALLED' };
    h.tts.listVoices = async () => [info];
    h.tts.downloadVoice = (_params, callback) => callback({ code: 1, message: 'failed' });
    await h.service.refreshVoices();
    const row = h.service.state.voices[0];
    await h.service.selectVoice(row);
    assert.equal(row.installed, false);
    assert.equal(h.service.state.person, 13);
    assert.equal(h.service.state.downloadingVoice, '');
    info.status = 'INSTALLED';
    await h.service.refreshVoices();
    assert.equal(h.service.state.voices[0], row);
    assert.equal(row.installed, true);
  });
  await check('分句保留原文字符偏移，长句不拆开代理对', async () => {
    const text = '  你好。”\n下一句！' + '文'.repeat(177) + '😀' + '字'.repeat(220);
    const parts = SpeechTextSegmenter.split(text);
    for (const part of parts) {
      assert.equal(text.slice(part.start, part.end).trim(), part.text);
      assert(!/^[\uDC00-\uDFFF]/.test(part.text)); assert(!/[\uD800-\uDBFF]$/.test(part.text));
      assert(part.end - part.start < 190);
    }
    assert.equal(SpeechTextSegmenter.indexAt(parts, parts[0].end), 1);
    assert.equal(SpeechTextSegmenter.indexAt(parts, text.length), parts.length);
  });
  await check('合成完成不提前翻句，播放完成才跨句和跨章', async () => {
    const h = harness(); await h.init(); await h.service.start(book(), 0, 0);
    h.complete(0); assert.equal(h.spoken.length, 1);
    h.complete(); assert.equal(h.spoken[1].text, '第二句！');
    h.complete(); await settle(); assert.equal(h.spoken[2].text, '第三句。');
    assert.equal(h.service.state.chapterIndex, 1);
    h.complete(); await settle(); assert.equal(h.service.state.playing, false); h.service.stop();
  });
  await check('暂停恢复当前句，旧回调与重复完成不能推进新请求', async () => {
    const h = harness(); await h.init(); await h.service.start(book(), 0, 5);
    const old = h.spoken.at(-1); h.service.pause(); await h.service.resume();
    assert.equal(h.spoken.at(-1).text, old.text);
    h.complete(1, old); assert.equal(h.service.state.chapterIndex, 0);
    const current = h.spoken.at(-1); h.complete(1, current); h.complete(1, current); await settle();
    assert.equal(h.spoken.length, 3); h.service.stop();
  });
  await check('重启后按章节 URL 恢复，目录重排不串章', async () => {
    const h = harness(); await h.init(); const b = book(); await h.service.start(b, 0, 5); h.service.stop();
    const next = harness(h.memory); await next.init(); b.chapters.reverse();
    await next.service.start(b, 0, 0, true);
    assert.equal(next.service.state.chapterIndex, 1); assert.equal(next.spoken[0].text, '第二句！'); next.service.stop();
  });
  await check('停止时取消尚未创建完成的引擎，不意外出声', async () => {
    const h = harness(); await h.init(); let finish;
    h.deferEngine(new Promise(resolve => { finish = resolve; }));
    const starting = h.service.start(book(), 0, 0); await settle(); h.service.stop(); finish(); await starting;
    assert.equal(h.spoken.length, 0); assert(h.engines.every(engine => engine.closed));
  });
  await check('读完本章停止，保留跨进程的章节末尾位置', async () => {
    const h = harness(); await h.init(); h.service.setSleep(0, true); await h.service.start(book(), 0, 0);
    h.complete(); h.complete(); await settle();
    assert.equal(h.service.state.chapterIndex, 0); assert.equal(h.service.state.playing, false);
    assert.equal(h.service.state.charOffset, '第一句。第二句！'.length); h.service.stop();
  });
  await check('音频抢占停止朗读、清理定时器并暂停系统播控', async () => {
    const h = harness(); await h.init(); await h.service.start(book(), 0, 0); h.service.setSleep(15);
    await h.coordinator.useAudio(); assert.equal(h.service.state.active, false);
    assert.equal(h.service.state.playing, false); assert.equal(h.timers.size, 0); assert(h.session.paused);
  });
  await check('耳机拔出与焦点丢失暂停，不自动外放续读', async () => {
    const h = harness(); await h.init(); await h.service.start(book(), 0, 0); h.unplug();
    assert.equal(h.service.state.playing, false); await h.service.resume(); h.focus();
    assert.equal(h.service.state.playing, false); h.service.stop();
  });
  await check('离线读缓存；正文失败停留当前章且能重试', async () => {
    const h = harness(); await h.init(); await h.service.start(book(), 0, 0); h.service.stop();
    h.failContent(true); await h.service.start(book(), 0, 0); assert.equal(h.service.state.playing, true);
    await h.service.start(book('other'), 0, 0); assert.equal(h.service.state.playing, false);
    assert(h.service.state.error.includes('content_error'));
    h.failContent(false); await h.service.resume(); assert.equal(h.service.state.playing, true); h.service.stop();
  });
  await check('语速切换持久化，正在播放时从当前句继续', async () => {
    const h = harness(); await h.init(); await h.service.start(book(), 0, 0); h.service.setSpeed(1.5); await settle();
    assert.equal(h.spoken.at(-1).speed, 1.5); assert.equal(h.spoken.length, 2);
    assert.equal(h.memory.get('speed'), 1.5); h.service.stop();
  });
  await check('初始化超时后可重试，迟到的引擎被释放', async () => {
    const h = harness(); await h.init(); let finish;
    h.deferEngine(new Promise(resolve => { finish = resolve; }));
    const pending = h.service.start(book(), 0, 0); await settle();
    const timeout = [...h.timers.values()].find(timer => timer.delay === 20000);
    assert(timeout); timeout.callback(); await pending;
    assert.equal(h.service.state.loading, false); assert(h.service.state.error);
    finish(); await settle(); assert(h.engines.every(engine => engine.closed));
    h.deferEngine(null); await h.service.resume(); assert.equal(h.service.state.playing, true); h.service.stop();
  });
  await check('稍后的朗读请求优先于仍在等待释放焦点的音频请求', async () => {
    const h = harness(); let finish;
    h.coordinator.speechActive = true;
    h.coordinator.stopSpeech = () => {
      h.coordinator.speechActive = false;
      return new Promise(resolve => { finish = resolve; });
    };
    const audioClaim = h.coordinator.useAudio();
    h.coordinator.speechActive = true; finish();
    assert.equal(await audioClaim, false); assert.equal(h.coordinator.speechActive, true);
  });
  await check('截止时间在下一句前检查，后台计时器延迟也不继续朗读', async () => {
    const h = harness(); await h.init(); await h.service.start(book(), 0, 0);
    h.service.setSleep(15); h.service.sleepDeadline = Date.now() - 1;
    h.complete(); assert.equal(h.spoken.length, 1); assert.equal(h.service.state.playing, false);
    assert.equal(h.service.state.remainingSeconds, 0); h.service.stop();
  });
  await check('会话空闲超时不停止独立进程 TTS，真实抢占仍暂停', async () => {
    const h = harness(); await h.init(); await h.service.start(book(), 0, 0);
    h.focus(1); assert.equal(h.service.state.playing, true);
    h.complete(); assert.equal(h.spoken.length, 2);
    h.focus(0); assert.equal(h.service.state.playing, false); h.service.stop();
  });
  await check('逐字游标映射段首缩进、跨段与表情，停在当前句末尾', async () => {
    const source = '你好。\n  世界😀！';
    const display = '　　你好。\n　　世界😀！';
    assert.equal(SpeechTextHighlighter.displayOffset(display, source, source.indexOf('世')), display.indexOf('世'));
    assert.equal(SpeechTextHighlighter.displayOffset(display, source, source.indexOf('😀')), display.indexOf('😀'));
    assert.equal(SpeechTextHighlighter.offsetAt('甲乙丙', 300, 260), 1);
    assert.equal(SpeechTextHighlighter.offsetAt('甲乙丙', 99999, 260), 2);
  });
  console.log(`${passed} TTS regressions passed`);
})().catch(error => { console.error(error); process.exitCode = 1; });
