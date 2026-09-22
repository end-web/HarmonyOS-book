// Real settings model/service with an in-memory HarmonyOS preferences adapter.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME to the installed DevEco Studio');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const values = new Map();
let flushes = 0;
const preferences = { getPreferences: async () => ({
  getSync: (key, fallback) => values.has(key) ? values.get(key) : fallback,
  putSync: (key, value) => values.set(key, value),
  flush: async () => { flushes++; }
}) };
const cache = new Map();
function load(relative) {
  const filename = path.resolve(root, relative.endsWith('.ets') ? relative : relative + '.ets');
  if (cache.has(filename)) return cache.get(filename);
  const exports = {};
  cache.set(filename, exports);
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInNewContext(code, { exports, require: name => {
    if (name === '@kit.ArkData') return { preferences };
    if (name.startsWith('@')) return {};
    return load(path.resolve(path.dirname(filename), name));
  }, console }, { filename });
  return exports;
}
(async () => {
  const { TextReadingSettings, PageTurnMode } = load('model/TextReading');
  const { TextReadingSettingsService: service } = load('service/text/TextReadingSettingsService');
  values.set('font_size', 22); // Existing installations have no new preference keys.
  const migrated = await service.get({});
  assert.equal(migrated.fontSize, 22);
  assert.equal(migrated.marginLeft, migrated.marginRight);
  assert.equal(migrated.followSystemTheme, false);
  assert.equal(migrated.alwaysShowStatusBar, true, 'existing installations show the status bar by default');
  migrated.followSystemTheme = true;
  migrated.alwaysShowStatusBar = false;
  migrated.pageTurnMode = PageTurnMode.Vertical;
  migrated.marginLeft = 8;
  migrated.marginRight = 26;
  migrated.marginTop = 32;
  migrated.marginBottom = 0;
  await service.save({}, migrated);
  const restored = await service.get({});
  assert.equal(restored.pageTurnMode, 'vertical');
  assert.equal(restored.followSystemTheme, true);
  assert.equal(restored.alwaysShowStatusBar, false, 'toolbar-following mode survives a preferences reload');
  assert.deepEqual([restored.marginLeft, restored.marginRight, restored.marginTop, restored.marginBottom], [8, 26, 32, 0]);
  values.set('marginLeft', -20);
  values.set('marginRight', 1000);
  values.set('marginTop', 'bad');
  values.set('marginBottom', NaN);
  values.set('page_turn_mode', 'bad');
  values.set('always_show_status_bar', 'bad');
  const sanitized = await service.get({});
  assert.deepEqual([sanitized.marginLeft, sanitized.marginRight, sanitized.marginTop, sanitized.marginBottom], [0, 64, 12, 12]);
  assert.equal(sanitized.pageTurnMode, PageTurnMode.Cover);
  assert.equal(sanitized.alwaysShowStatusBar, true, 'invalid status-bar preference falls back to visible');
  await service.save({}, new TextReadingSettings());
  const reset = await service.get({});
  assert.equal(reset.followSystemTheme, false);
  assert.equal(reset.alwaysShowStatusBar, true);
  assert.equal(reset.marginLeft, 16);
  assert.equal(reset.marginRight, 16);
  assert.equal(flushes, 2);
  const { ReaderThemeId, resolvePalette } = load('model/ReaderTheme');
  const custom = new TextReadingSettings();
  custom.themeId = ReaderThemeId.Black;
  custom.pageTurnMode = PageTurnMode.None;
  await service.save({}, custom);
  const customRestored = await service.get({});
  assert.equal(customRestored.themeId, 'black');
  assert.equal(customRestored.pageTurnMode, 'none');
  assert.equal(resolvePalette(customRestored.themeId, '').background, '#000000');
  const typography = new TextReadingSettings();
  typography.fontSize = 50;
  typography.lineHeight = 1;
  typography.fontWeight = 537;
  typography.fontColor = '#123456';
  typography.fontName = 'Test.ttf';
  typography.fontPath = '/data/storage/el2/base/files/reader_fonts/test.ttf';
  typography.themeId = ReaderThemeId.Custom;
  typography.customBackground = '#BADA55';
  typography.screenOnMinutes = 5;
  await service.save({}, typography);
  const fontRestored = await service.get({});
  for (const field of ['fontSize', 'lineHeight', 'fontWeight', 'fontColor', 'fontName', 'fontPath',
    'themeId', 'customBackground', 'screenOnMinutes']) assert.equal(fontRestored[field], typography[field], field);
  assert.equal(TextReadingSettings.normalizeFontSize(100), 50);
  assert.equal(TextReadingSettings.normalizeLineHeight(0), 1);
  assert.equal(TextReadingSettings.normalizeFontWeight(NaN), 400);
  assert.equal(TextReadingSettings.normalizeFontWeight(950), 900);
  assert.equal(TextReadingSettings.normalizeScreenOnMinutes(7), 0);
  for (const minutes of [0, 1, 5, 10, -1]) {
    typography.screenOnMinutes = minutes;
    await service.save({}, typography);
    assert.equal((await service.get({})).screenOnMinutes, minutes);
  }
  console.log('PASS: legacy preferences, vertical mode, four margins, system theme, invalid values, reset, custom typography/colors/fonts, screen timeout');
})().catch(error => { console.error(error); process.exitCode = 1; });
