// Real font library service: batch selection, persistence and partial failure.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const fsp = fs.promises;
const path = require('node:path');
const os = require('node:os');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'hsda-fonts-')).replaceAll('\\', '/');
const handles = new Map();
const values = new Map();
let selected = [];
let selectionLimit = 0;
const fileIo = {
  OpenMode: { READ_ONLY: 0 },
  async access(filename) { return fs.existsSync(filename); },
  accessSync: fs.existsSync,
  async open(filename) { const file = await fsp.open(filename, 'r'); handles.set(file.fd, file); return file; },
  async close(file) { handles.delete(file.fd); await file.close(); },
  async stat(fd) { return handles.get(fd).stat(); },
  async read(fd, data, options) {
    return (await handles.get(fd).read(Buffer.from(data), 0, options.length, options.offset)).bytesRead;
  },
  async copyFile(fd, dest) {
    const source = handles.get(fd);
    const bytes = Buffer.alloc((await source.stat()).size);
    await source.read(bytes, 0, bytes.length, 0);
    await fsp.writeFile(dest, bytes);
  },
  async mkdir(dir) { if (fs.existsSync(dir)) throw new Error('File exists'); await fsp.mkdir(dir, { recursive: true }); },
  listFile: dir => fsp.readdir(dir),
  unlink: file => fsp.unlink(file)
};
function load() {
  const exports = {};
  const file = path.resolve(__dirname, '../entry/src/main/ets/service/text/ReaderFontService.ets');
  const code = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInNewContext(code, { exports, console, ArrayBuffer, Uint8Array, require: name => {
    if (name === '@kit.CoreFileKit') return { fileIo, picker: {
      DocumentSelectOptions: class {}, DocumentViewPicker: class {
        async select(options) { selectionLimit = options.maxSelectNumber; return selected; }
      }
    } };
    if (name === '@kit.ArkData') return { preferences: { getPreferences: async () => ({
      getSync: (key, fallback) => values.get(key) ?? fallback,
      putSync: (key, value) => values.set(key, value), flush: async () => {}
    }) } };
    if (name === '@kit.ArkGraphics2D') return { text: { FontCollection: {
      getGlobalInstance: () => ({ loadFontSync: () => {} })
    } } };
    return {};
  } }, { filename: file });
  return exports.ReaderFontService;
}
(async () => {
  const context = { filesDir: temp };
  let service = load();
  assert.equal((await service.list(context)).length, 0);
  for (let i = 0; i < 7; i++) {
    const bytes = Buffer.alloc(64); bytes[1] = 1; bytes[10] = i;
    await fsp.writeFile(`${temp}/Test-${i}.ttf`, bytes);
  }
  selected = [0, 1, 2, 3, 4].map(i => `${temp}/Test-${i}.ttf`);
  const first = await service.pick(context);
  assert.equal(selectionLimit, 5);
  assert.equal(first.fonts.length, 5);
  assert.equal(new Set(first.fonts.map(font => font.path)).size, 5);
  assert.equal(first.fonts.at(-1).name, 'Test-4.ttf');
  await fsp.writeFile(`${temp}/broken.ttf`, 'not a font at all');
  selected = [`${temp}/Test-5.ttf`, `${temp}/broken.ttf`, `${temp}/Test-6.ttf`];
  const second = await service.pick(context);
  assert.equal(second.fonts.length, 2);
  assert.equal(second.failures.length, 1);
  service = load(); // process restart
  const library = await service.list(context);
  assert.equal(library.length, 7);
  assert.ok(library.some(font => font.name === 'Test-0.ttf'), 'old font remains selectable');
  for (const font of library) assert.ok(service.register(context, font.path).startsWith('ReaderFont_'));
  selected = [];
  assert.equal((await service.pick(context)).fonts.length, 0);
  assert.equal((await service.list(context)).length, 7, 'cancel does not erase library');
  const deleted = library[0];
  const remaining = await service.remove(context, deleted.path);
  assert.equal(remaining.length, 6);
  assert.ok(!fs.existsSync(deleted.path));
  assert.equal((await load().list(context)).length, 6, 'deleted font stays removed after restart');
  await assert.rejects(service.remove(context, `${temp}/Test-0.ttf`));
  assert.ok(fs.existsSync(`${temp}/Test-0.ttf`), 'cannot delete outside the font library');
  assert.equal(handles.size, 0);
  console.log('PASS: five-font selection, unique files, retained library, restart, partial failure, cancellation');
})().catch(error => { console.error(error); process.exitCode = 1; })
  .finally(() => fs.rmSync(temp, { recursive: true, force: true }));
