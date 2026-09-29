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
  getAll: async () => Object.fromEntries(values),
  deleteSync: key => values.delete(key),
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
  vm.runInNewContext(code, { exports, ObservedV2: value => value, Trace: () => {}, require: name => {
    if (name === '@kit.ArkData') return { preferences };
    if (name === '@kit.BasicServicesKit') return { emitter: { emit() {} } };
    if (name === './TextToSpeechService') return { TextToSpeechService: { reloadSettings: async () => {} } };
    if (name.startsWith('@')) return {};
    return load(path.resolve(path.dirname(filename), name));
  }, console }, { filename });
  return exports;
}
(async () => {
  const { TextReadingSettings, PageTurnMode } = load('model/TextReading');
  assert.equal(new TextReadingSettings().textAlignment, 'justify');
  assert.equal(TextReadingSettings.normalizeTextAlignment('invalid'), 'justify');
  const { TextReadingSettingsService: service } = load('service/text/TextReadingSettingsService');
  values.set('font_size', 22); // Existing installations have no new preference keys.
  const migrated = await service.get({});
  assert.equal(migrated.fontSize, 22);
  assert.equal(migrated.textAlignment, 'justify', 'legacy preferences default to justified text');
  assert.equal(migrated.marginLeft, migrated.marginRight);
  assert.equal(migrated.followSystemTheme, false);
  assert.equal(migrated.alwaysShowStatusBar, true, 'existing installations show the status bar by default');
  assert.equal(migrated.volumeKeyPageTurn, false);
  migrated.volumeKeyPageTurn = true;
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
  assert.equal(restored.volumeKeyPageTurn, true);
  assert.equal(restored.followSystemTheme, true);
  assert.equal(restored.alwaysShowStatusBar, false, 'toolbar-following mode survives a preferences reload');
  assert.deepEqual([restored.marginLeft, restored.marginRight, restored.marginTop, restored.marginBottom], [8, 26, 32, 0]);
  values.set('marginLeft', -20);
  values.set('marginRight', 1000);
  values.set('marginTop', 'bad');
  values.set('marginBottom', NaN);
  values.set('volume_key_page_turn', 'bad');
  values.set('page_turn_mode', 'bad');
  values.set('always_show_status_bar', 'bad');
  const sanitized = await service.get({});
  assert.deepEqual([sanitized.marginLeft, sanitized.marginRight, sanitized.marginTop, sanitized.marginBottom], [0, 64, 12, 12]);
  assert.equal(sanitized.pageTurnMode, PageTurnMode.Cover);
  assert.equal(sanitized.volumeKeyPageTurn, false);
  assert.equal(sanitized.alwaysShowStatusBar, true, 'invalid status-bar preference falls back to visible');
  await service.save({}, new TextReadingSettings());
  const reset = await service.get({});
  assert.equal(reset.followSystemTheme, false);
  assert.equal(reset.volumeKeyPageTurn, false);
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
  for (const alignment of ['justify', 'start', 'center', 'end']) {
    typography.textAlignment = alignment;
    await service.save({}, typography);
    assert.equal((await service.get({})).textAlignment, alignment);
  }
  values.set('text_alignment', 'invalid');
  assert.equal((await service.get({})).textAlignment, 'justify');
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
  const { ReadingBackupService: backup } = load('service/text/ReadingBackupService');
  typography.volumeKeyPageTurn = true;
  typography.textAlignment = 'end';
  await service.save({}, typography);
  const snapshot = await backup.createSnapshot({});
  assert.equal(snapshot.settings.textAlignment, 'end');
  assert.equal(snapshot.settings.volumeKeyPageTurn, true);
  await service.save({}, new TextReadingSettings());
  await backup.restoreSnapshot({}, snapshot);
  assert.equal((await service.get({})).textAlignment, 'end');
  assert.equal((await service.get({})).volumeKeyPageTurn, true);
  delete snapshot.settings.volumeKeyPageTurn;
  delete snapshot.settings.textAlignment;
  await backup.restoreSnapshot({}, snapshot);
  assert.equal((await service.get({})).textAlignment, 'justify', 'old backups adopt justified text');
  assert.equal((await service.get({})).volumeKeyPageTurn, false, 'old backups keep system volume behavior');
  // Theme ownership: custom colors must never leak into a preset or image theme.
  const { resolveEffectiveThemeId, readerColorContrast, recommendedReaderFontColor } = load('model/ReaderTheme');
  const themeSettings = new TextReadingSettings();
  themeSettings.themeId = ReaderThemeId.Custom;
  themeSettings.customBackground = '#E8DBB8';
  themeSettings.fontColor = '#453321';
  themeSettings.backgroundImage = '/data/storage/el2/base/files/reader_bg/test.jpg';
  themeSettings.imageBackground = '#1C1F22';
  themeSettings.imageFontColor = '#F5F2EA';
  themeSettings.overlayAlpha = 0.6;
  for (const id of [ReaderThemeId.Custom, ReaderThemeId.Image, ReaderThemeId.Night,
    ReaderThemeId.Black, ReaderThemeId.Parchment, ReaderThemeId.Custom, ReaderThemeId.Image]) {
    themeSettings.themeId = id;
    themeSettings.pattern = id === ReaderThemeId.Image ? 'image' : 'none';
    await service.save({}, themeSettings);
    const saved = await service.get({});
    assert.equal(saved.themeId, id);
    assert.equal(saved.customBackground, '#E8DBB8');
    assert.equal(saved.fontColor, '#453321');
    assert.equal(saved.imageBackground, '#1C1F22');
    assert.equal(saved.imageFontColor, '#F5F2EA');
    assert.equal(saved.backgroundImage, themeSettings.backgroundImage);
    assert.equal(saved.overlayAlpha, 0.6);
    const palette = resolvePalette(id, saved.customBackground, saved.fontColor,
      saved.imageBackground, saved.imageFontColor);
    if (id === ReaderThemeId.Custom) {
      assert.equal(palette.background, '#E8DBB8');
      assert.equal(palette.primary, '#453321');
    } else if (id === ReaderThemeId.Image) {
      assert.equal(palette.background, '#1C1F22');
      assert.equal(palette.primary, '#F5F2EA');
    } else {
      assert.equal(palette.primary, resolvePalette(id, '').primary, 'preset owns its text color');
      assert.equal(palette.background, resolvePalette(id, '').background);
    }
    assert.equal(resolveEffectiveThemeId(id, false, true), id);
    assert.equal(resolveEffectiveThemeId(id, true, true), ReaderThemeId.Night);
    assert.equal(resolveEffectiveThemeId(id, true, false),
      [ReaderThemeId.Night, ReaderThemeId.Black].includes(id) ? ReaderThemeId.Parchment : id);
  }
  assert.equal(readerColorContrast('#FFFFFF', '#FFFFFF'), 1);
  assert.equal(readerColorContrast('#FFFFFF', '#000000'), 21);
  for (const bg of ['#000000', '#FFFFFF', '#E8DBB8', '#777777']) {
    assert.ok(readerColorContrast(bg, recommendedReaderFontColor(bg)) > 3);
  }
  // Legacy global text colors are captured in a custom theme with the visible old background.
  values.clear();
  values.set('theme_id', 'black');
  values.set('font_color', '#BADA55');
  const legacyText = await service.get({});
  assert.equal(legacyText.themeId, ReaderThemeId.Custom);
  assert.equal(legacyText.customBackground, '#000000');
  assert.equal(legacyText.fontColor, '#BADA55');
  await service.save({}, legacyText);
  legacyText.themeId = ReaderThemeId.Black;
  await service.save({}, legacyText);
  assert.equal((await service.get({})).themeId, ReaderThemeId.Black, 'migration does not run twice');
  // Legacy image tint and global text color become independent image settings.
  values.clear();
  values.set('theme_id', 'image');
  values.set('background_pattern', 'image');
  values.set('background_image', themeSettings.backgroundImage);
  values.set('custom_background', '#204060');
  values.set('font_color', '#EECCAA');
  values.set('overlay_alpha', 0.7);
  const legacyImage = await service.get({});
  assert.equal(legacyImage.themeId, ReaderThemeId.Image);
  assert.equal(legacyImage.imageBackground, '#204060');
  assert.equal(legacyImage.imageFontColor, '#EECCAA');
  assert.equal(legacyImage.overlayAlpha, 0.7);
  await service.save({}, legacyImage);
  legacyImage.themeId = ReaderThemeId.Custom;
  legacyImage.pattern = 'none';
  legacyImage.customBackground = '#FFFFFF';
  legacyImage.fontColor = '#000000';
  await service.save({}, legacyImage);
  assert.equal((await service.get({})).imageBackground, '#204060');
  assert.equal((await service.get({})).imageFontColor, '#EECCAA');
  values.clear();
  values.set('theme_id', 'night');
  assert.equal((await service.get({})).themeId, ReaderThemeId.Night, 'unmodified legacy preset stays a preset');
  const { ReaderCustomTheme, isReaderHexColor, normalizeHex } = load('model/ReaderTheme');
  values.clear();
  values.set('theme_id', 'custom');
  values.set('custom_background', '#ABCDEF');
  values.set('font_color', '#123456');
  const fiveThemes = await service.get({});
  assert.equal(fiveThemes.customThemes.length, 5);
  assert.equal(fiveThemes.customThemeIndex, 0);
  assert.equal(fiveThemes.customThemes[0].background, '#ABCDEF');
  assert.equal(fiveThemes.customThemes[0].fontColor, '#123456');
  assert.equal(new Set(fiveThemes.customThemes.map(theme => theme.id)).size, 5);
  const slotColors = ['#111111', '#222222', '#333333', '#444444', '#555555'];
  for (let slot = 0; slot < 5; slot++) {
    fiveThemes.customThemeIndex = slot;
    fiveThemes.customBackground = slotColors[slot];
    fiveThemes.fontColor = '#FEDCBA';
    fiveThemes.customThemes[slot] = ReaderCustomTheme.of(slot, slotColors[slot], '#FEDCBA');
    await service.save({}, fiveThemes);
  }
  for (let slot = 0; slot < 5; slot++) {
    const loaded = await service.get({});
    assert.equal(loaded.customThemes[slot].background, slotColors[slot]);
    assert.equal(loaded.customThemes[slot].fontColor, '#FEDCBA');
  }
  assert.equal((await service.get({})).customThemeIndex, 4);
  assert.equal((await service.get({})).customBackground, '#555555');
  values.set('custom_theme_index', 100);
  assert.equal((await service.get({})).customThemeIndex, 0);
  for (const text of ['#123', 'abc', '#aAbBcC', 'AABBCC', ' #123456 ']) assert.equal(isReaderHexColor(text), true);
  for (const text of ['', '#', '#12', '#12345', '#1234567', '#GGGGGG', '#12345678']) assert.equal(isReaderHexColor(text), false);
  assert.equal(normalizeHex('#abc'), '#AABBCC');
  console.log('PASS: five independent theme slots, legacy single-theme migration, selected-slot reload, manual HEX validation');
  console.log('PASS: theme isolation, switching/reload, system override, legacy color/image migration, contrast');
  console.log('PASS: settings migration/reset, four alignments, persistence, backup round trip, legacy backup, typography and margins');
})().catch(error => { console.error(error); process.exitCode = 1; });
