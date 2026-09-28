// Real WindowUtils with simulated API 20/22 safe areas; no device/system settings are changed.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/utils/WindowUtils.ets'), 'utf8');
const code = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
// Run the actual navigation handler as well: going Home hides the destination without changing its stack.
let indexSource = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/pages/Index.ets'), 'utf8');
indexSource = indexSource.slice(0, indexSource.indexOf('  @Builder')) + '\n}';
indexSource = indexSource.replace('@Entry', '').replace('@ComponentV2', '')
  .replace('struct Index', 'export class Index').replace(/@Local\s+/g, '');
const indexCode = ts.transpileModule(indexSource, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
function environment(api, failingNewApi = false) {
  const exports = {};
  let visible = true;
  let top = 90;
  let width = 1200;
  let cutoutTop = 60;
  let windowStatus = 'fullscreen';
  const visibility = [];
  let cutoutLeft = 0;
  let cutoutRight = 0;
  let navigationRight = 0;
  const area = (height, bottom = 0, left = 0, right = 0) => ({
    topRect: { top: 0, left: 0, width: 0, height },
    bottomRect: { top: 0, left: 0, width: 0, height: bottom },
    leftRect: { top: 0, left: left > 0 ? 12 : 0, width: left, height: left > 0 ? 60 : 0 },
    rightRect: { top: 0, left: right > 0 ? 1200 - right - 12 : 0, width: right, height: right > 0 ? 60 : 0 }
  });
  const win = {
    getWindowProperties: () => ({ windowRect: { width } }),
    getWindowDensityInfo: () => ({ customDensity: 0, systemDensity: 3 }),
    getWindowStatus: () => windowStatus,
    getWindowAvoidArea: type => windowStatus === 'minimized' ? area(0) : type === 'system' ? area(visible ? top : 0) :
      type === 'cutout' ? area(cutoutTop, 0, cutoutLeft, cutoutRight) : area(0, 30, 0, navigationRight),
    getWindowAvoidAreaIgnoringVisibility: () => {
      assert.ok(api >= 22, 'API 20 must not invoke the API 22 interface');
      if (failingNewApi) throw new Error('unavailable');
      return area(top);
    },
    setSpecificSystemBarEnabled: async (_name, value) => { visible = value; visibility.push(value); },
    setWindowSystemBarProperties: async () => {}
  };
  const mocks = {
    '@kit.ArkUI': { window: { AvoidAreaType: {
      TYPE_SYSTEM: 'system', TYPE_NAVIGATION_INDICATOR: 'navigation', TYPE_CUTOUT: 'cutout', TYPE_FLOAT_NAVIGATION: 'floating'
    }, WindowStatusType: { FULL_SCREEN: 'fullscreen', MINIMIZE: 'minimized' } } },
    '@kit.AbilityKit': { ConfigurationConstant: { ColorMode: { COLOR_MODE_LIGHT: 0, COLOR_MODE_DARK: 1 } } },
    './PlatformCompat': { PlatformCompat: { supports: version => api >= version } }
  };
  vm.runInNewContext(code, { exports, require: name => mocks[name], setTimeout: () => 1, clearTimeout() {} });
  const utils = exports.WindowUtils;
  utils.mainWindow = win;
  utils.syncAvoidArea(win);
  const indexExports = {};
  vm.runInNewContext(indexCode, {
    exports: indexExports, require: name => name === '../utils/WindowUtils' ? { WindowUtils: utils } : {}
  });
  const routes = ['home', 'reader'];
  const index = Object.create(indexExports.Index.prototype);
  index.navStack = { getAllPathName: () => routes };
  return { utils, visibility, routes, syncRoute: () => index.syncReaderWindowMode(),
    rotate: () => { width = 2400; top = 36; cutoutTop = 0; utils.refreshAvoidArea(); },
    setWindowStatus: value => { windowStatus = value; },
    setSideAreas: (left, right, navRight = 0) => {
      cutoutLeft = left;
      cutoutRight = right;
      navigationRight = navRight;
      utils.handleAvoidAreaChange();
    } };
}
(async () => {
  for (const [api, fallback] of [[20, false], [22, false], [22, true], [26, false]]) {
    const { utils, visibility, routes, syncRoute, setWindowStatus, setSideAreas, rotate } = environment(api, fallback);
    const observedSides = [];
    const sideListener = () => observedSides.push([utils.getLeftSafeVp(), utils.getRightSafeVp()]);
    utils.addSafeAreaListener(sideListener);
    setSideAreas(84, 0);
    assert.equal(utils.getLeftSafeVp(), 32, 'left cutout clearance includes the gap to the window edge');
    assert.equal(utils.getRightSafeVp(), 0);
    setSideAreas(0, 84);
    assert.equal(utils.getLeftSafeVp(), 0, 'rotating must clear the old camera side');
    assert.equal(utils.getRightSafeVp(), 32, 'right cutout clearance is measured from the window edge');
    setSideAreas(84, 60, 108);
    assert.equal(utils.getLeftSafeVp(), 32);
    assert.equal(utils.getRightSafeVp(), 40, 'side system navigation uses the larger inset');
    setSideAreas(0, 0);
    assert.deepEqual(observedSides, [[0, 0], [32, 0], [0, 32], [32, 40], [0, 0]],
      'side-only changes must notify page listeners and portrait must clear side insets');
    utils.removeSafeAreaListener(sideListener);
    syncRoute();
    await utils.readerStatusBarUpdate;
    assert.equal(visibility.at(-1), true, 'status bar is visible by default');
    const safeTop = utils.getStatusBarHeightVp();
    assert.equal(safeTop, 30);
    for (const visible of [false, true, false, true]) {
      utils.setReaderStatusBarVisible(visible);
      await utils.readerStatusBarUpdate;
      assert.equal(visibility.at(-1), visible);
      assert.equal(utils.getStatusBarHeightVp(), safeTop, 'toolbar visibility must never resize the reading area');
    }
    const observedInsets = [];
    utils.addSafeAreaListener((top, bottom) => observedInsets.push([top, bottom]));
    const stableInsets = observedInsets[0];
    let colorChanges = 0;
    utils.addReaderColorListener(() => colorChanges++);
    for (const fixedStatus of [true, false]) {
      utils.setReaderStatusBarVisible(fixedStatus);
      await utils.readerStatusBarUpdate;
      const visibilityCount = visibility.length;
      for (let repeat = 0; repeat < 3; repeat++) {
        setWindowStatus('minimized');
        syncRoute();
        utils.refreshAvoidArea();
        await utils.readerStatusBarUpdate;
        setWindowStatus('fullscreen');
        utils.updateColorMode(0);
        syncRoute();
        utils.refreshAvoidArea();
        await utils.readerStatusBarUpdate;
      }
      assert.equal(visibility.length, visibilityCount, 'Home and resume must not toggle the reader status bar');
      assert.equal(colorChanges, 0, 'an unchanged foreground theme must not rebuild reader colors');
      assert.ok(observedInsets.every(insets => insets[0] === stableInsets[0] && insets[1] === stableInsets[1]),
        'minimized avoid areas must not resize the reader');
    }
    utils.updateColorMode(1);
    utils.updateColorMode(1);
    assert.equal(colorChanges, 1, 'a real system theme change must notify the reader exactly once');
    await utils.setReaderStatusBarLight(false);
    assert.equal(utils.getSystemBarContentColor(), '#FF000000', 'light paper needs dark text even with a dark system theme');
    await utils.setReaderStatusBarLight(true);
    assert.equal(utils.getSystemBarContentColor(), '#FFFFFFFF');
    utils.setReaderStatusBarVisible(false);
    await utils.readerStatusBarUpdate;
    routes.push('detail');
    syncRoute();
    await utils.readerStatusBarUpdate;
    assert.equal(visibility.at(-1), true, 'leaving the reader restores the system bar');
    routes.pop();
    syncRoute();
    await utils.readerStatusBarUpdate;
    assert.equal(visibility.at(-1), false, 'returning from details restores toolbar-following visibility');
    assert.equal(utils.getStatusBarHeightVp(), safeTop);
    utils.setReaderStatusBarVisible(true);
    await utils.readerStatusBarUpdate;
    rotate();
    assert.equal(utils.getStatusBarHeightVp(), 12, 'landscape clears stale portrait inset');
    assert.equal(utils.getCutoutTopVp(), 0, 'landscape top has no camera gap');
  }
  console.log('PASS: API 20/22/26 and fallback, repeated Home/resume with either status mode, stable insets, theme changes, details route restore');
})().catch(error => { console.error(error); process.exitCode = 1; });
