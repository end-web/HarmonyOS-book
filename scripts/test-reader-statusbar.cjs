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
function environment(api, failingNewApi = false) {
  const exports = {};
  let visible = true;
  let top = 90;
  const visibility = [];
  const area = (height, bottom = 0) => ({ topRect: { height }, bottomRect: { height: bottom } });
  const win = {
    getWindowDensityInfo: () => ({ customDensity: 0, systemDensity: 3 }),
    getWindowStatus: () => 'fullscreen',
    getWindowAvoidArea: type => type === 'system' ? area(visible ? top : 0) :
      type === 'cutout' ? area(60) : area(0, 30),
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
      TYPE_SYSTEM: 'system', TYPE_NAVIGATION_INDICATOR: 'navigation', TYPE_CUTOUT: 'cutout'
    }, WindowStatusType: { FULL_SCREEN: 'fullscreen' } } },
    '@kit.AbilityKit': { ConfigurationConstant: { ColorMode: { COLOR_MODE_LIGHT: 0, COLOR_MODE_DARK: 1 } } },
    './PlatformCompat': { PlatformCompat: { supports: version => api >= version } }
  };
  vm.runInNewContext(code, { exports, require: name => mocks[name], setTimeout: () => 1, clearTimeout() {} });
  const utils = exports.WindowUtils;
  utils.mainWindow = win;
  utils.syncAvoidArea(win);
  return { utils, visibility, setTop: value => { top = value; } };
}
(async () => {
  for (const [api, fallback] of [[20, false], [22, false], [22, true]]) {
    const { utils, visibility } = environment(api, fallback);
    utils.setReaderActive(true);
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
    utils.updateColorMode(1);
    await utils.setReaderStatusBarLight(false);
    assert.equal(utils.getSystemBarContentColor(), '#FF000000', 'light paper needs dark text even with a dark system theme');
    await utils.setReaderStatusBarLight(true);
    assert.equal(utils.getSystemBarContentColor(), '#FFFFFFFF');
    utils.setReaderStatusBarVisible(false);
    await utils.readerStatusBarUpdate;
    utils.setReaderActive(false);
    await utils.readerStatusBarUpdate;
    assert.equal(visibility.at(-1), true, 'leaving the reader restores the system bar');
    utils.setReaderActive(true);
    await utils.readerStatusBarUpdate;
    assert.equal(visibility.at(-1), false, 'returning from details restores toolbar-following visibility');
    assert.equal(utils.getStatusBarHeightVp(), safeTop);
  }
  console.log('PASS: default visibility, stable safe area on API 20/22 and fallback, toolbar toggles, contrast, route restore');
})().catch(error => { console.error(error); process.exitCode = 1; });
