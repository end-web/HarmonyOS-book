// Real import/persistence services with temporary files and platform adapters.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const fsp = fs.promises;
const path = require('node:path');
const os = require('node:os');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'hsda-import-test-'));
const context = { filesDir: temp.replaceAll('\\', '/'), cacheDir: temp.replaceAll('\\', '/') + '/cache' };
const handles = new Map();
let free = 256 * 1024 ** 3;
const fileIo = {
  OpenMode: { READ_ONLY: 0, CREATE: 1, WRITE_ONLY: 2, TRUNC: 4, READ_WRITE: 8 },
  async open(filename, flags) {
    const handle = await fsp.open(filename, flags ? 'w+' : 'r');
    handles.set(handle.fd, handle); return { fd: handle.fd };
  },
  async close(file) { const fd = typeof file === 'number' ? file : file.fd; await handles.get(fd).close(); handles.delete(fd); },
  async stat(file) { return typeof file === 'number' ? handles.get(file).stat() : fsp.stat(file); },
  async read(fd, buffer, options) {
    return (await handles.get(fd).read(Buffer.from(buffer), 0, options.length, options.offset)).bytesRead;
  },
  async write(fd, text) { return (await handles.get(fd).write(text)).bytesWritten; },
  async copyFile(source, target) { await handles.get(target).writeFile(await handles.get(source).readFile()); },
  mkdir: (directory) => fsp.mkdir(directory, { recursive: true }),
  rmdir: (directory) => fsp.rm(directory, { recursive: true, force: true }),
  readText: (filename) => fsp.readFile(filename, 'utf8'),
  async access(filename) { try { await fsp.access(filename); return true; } catch { return false; } },
  moveFile: (a, b) => fsp.rename(a, b),
  unlink: filename => fsp.unlink(filename),
  fsync: fd => handles.get(fd).sync()
};
const values = new Map();
const preference = {
  async getImportedBooks() { return values.get('books') || '[]'; },
  async saveImportedBooks(json) { values.set('books', json); }
};
const modules = new Map();
function load(relative) {
  const filename = path.resolve(root, relative.endsWith('.ets') ? relative : relative + '.ets');
  if (modules.has(filename)) return modules.get(filename);
  const exports = {}; modules.set(filename, exports);
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInNewContext(code, { exports, console, ArrayBuffer, Uint8Array, setTimeout, require: name => {
    if (name === '@kit.CoreFileKit') return { fileIo, statfs: { getFreeSize: async () => free } };
    if (name === '@kit.ArkTS') return { util: { TextDecoder: { create(encoding, options) {
      const decoder = new TextDecoder(encoding, options);
      return { decodeToString: (bytes, opts) => decoder.decode(bytes, opts) };
    } } } };
    if (name === '@kit.BasicServicesKit') return { zlib: { getOriginalSize: async () => 1024 } };
    if (name === '@hms.core.readerservice.bookParser') return { bookParser: {
      getDefaultHandler: async () => ({
        getBookInfo: () => ({ bookTitle: 'EPUB 标题', bookCreator: '作者' }),
        getSpineList: () => [{ idRef: 'a' }, { idRef: 'b' }],
        getCatalogList: () => [{ idRef: 'a', catalogName: '第一章' }, { idRef: 'b', catalogName: '第二章' }],
        getSpineItemContent: async index => `<body><p>章节 ${index + 1}</p><script>bad()</script></body>`
      })
    } };
    if (name.endsWith('/PreferenceService')) return { PreferenceService: preference };
    if (name.startsWith('@')) return {};
    return load(path.resolve(path.dirname(filename), name));
  } }, { filename });
  return exports;
}
(async () => {
  const { LocalBookImportService: service } = load('service/LocalBookImportService');
  const { DataService: data } = load('service/DataService');
  data.ctx = context; data.migrationPromise = Promise.resolve();
  const file = { uri: path.join(temp, 'novel.txt'), name: '小说', ext: '.txt' };
  const source = '第一章 初见\n你好世界\n第二章 重逢\n' + '文字😀'.repeat(20000);
  await fsp.writeFile(file.uri, source);
  const book = await service.importBook(context, file, 'import_123_text_0', '', '', '', () => {});
  assert.ok(book.chapters.length >= 3);
  assert.equal(book.chapters[0].title, '第一章 初见');
  const texts = await Promise.all(book.chapters.map(ch => fsp.readFile(ch.source.value, 'utf8')));
  assert.ok(texts.every(text => text.length <= 32000 && !text.includes('\uFFFD')));
  assert.equal(texts.join('').replaceAll('\n', ''), source.replaceAll('\n', ''));
  await data.addImportedBook(book);
  assert.equal(JSON.parse(values.get('books'))[0].chapters.length, 0);
  data.cache = null;
  const restored = await data.getBookById(context, book.id);
  assert.equal(restored.chapters.length, book.chapters.length);
  assert.equal(await data.readImportedText(restored, restored.chapters[0].source.value), texts[0]);
  await assert.rejects(() => data.readImportedText(restored, context.filesDir + '/other.txt'));

  for (const [name, bytes, expected] of [
    ['utf16', Buffer.concat([Buffer.from([0xff, 0xfe]), Buffer.from('中文内容', 'utf16le')]), '中文内容'],
    ['gb18030', Buffer.from([0xd6, 0xd0, 0xce, 0xc4]), '中文']
  ]) {
    await fsp.writeFile(file.uri, bytes);
    const result = await service.importBook(context, file, 'import_' + name, '', '', '', () => {});
    assert.equal(await fsp.readFile(result.chapters[0].source.value, 'utf8'), expected);
  }
  file.ext = '.html';
  await fsp.writeFile(file.uri, '<html><head><title>ignore</title></head><body><h1>章节</h1><p>甲&amp;乙</p><script>bad()</script><p>尾声</p></body></html>');
  const html = await service.importBook(context, file, 'import_html', '', '', '', () => {});
  assert.equal(await fsp.readFile(html.chapters[0].source.value, 'utf8'), '章节\n\n甲&乙\n\n尾声');
  file.ext = '.epub';
  const epub = await service.importBook(context, file, 'import_epub', '', '', '', () => {});
  assert.equal(epub.title, 'EPUB 标题');
  assert.equal(epub.chapters.map(ch => ch.title).join(','), '第一章,第二章');
  assert.equal(await fsp.readFile(epub.chapters[1].source.value, 'utf8'), '章节 2');

  free = 0;
  await assert.rejects(() => service.importBook(context, file, 'import_full', '', '', '', () => {}), /空间不足/);
  assert.equal(fs.existsSync(path.join(temp, 'ebooks/import_full')), false);
  await data.removeImportedBook(book.id);
  assert.equal(fs.existsSync(path.join(temp, 'ebooks', book.id)), false);
  assert.equal(fs.existsSync(path.join(temp, 'imported_toc', book.id + '.json')), false);
  assert.equal(handles.size, 0);
  console.log('PASS: streaming chapters, Unicode/GB18030, HTML, EPUB adapter, restart persistence, space failure, deletion');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(async () => {
  for (const handle of handles.values()) await handle.close();
  await fsp.rm(temp, { recursive: true, force: true });
});
