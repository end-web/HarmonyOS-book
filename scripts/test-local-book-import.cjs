// Real import/persistence services with temporary files and platform adapters.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const fsp = fs.promises;
const path = require('node:path');
const os = require('node:os');
const vm = require('node:vm');
const { mobiFixture, MOBI_COVER_PNG } = require('./mobi-fixture.cjs');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'hsda-import-test-'));
const context = { filesDir: temp.replaceAll('\\', '/'), cacheDir: temp.replaceAll('\\', '/') + '/cache' };
const strings = new Map(JSON.parse(fs.readFileSync(path.join(root, '../resources/base/element/string.json'), 'utf8'))
  .string.map(item => [item.name, item.value]));
context.resourceManager = { getStringByNameSync: name => strings.get(name) };
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
  async write(fd, text) { return (await handles.get(fd).write(typeof text === 'string' ? text : Buffer.from(text))).bytesWritten; },
  async copyFile(source, target) { await handles.get(target).writeFile(await handles.get(source).readFile()); },
  async mkdir(directory) {
    // HarmonyOS recursive mkdir still reports EEXIST for an existing leaf directory.
    if (fs.existsSync(directory)) throw new Error('File exists');
    await fsp.mkdir(directory, { recursive: true });
  },
  rmdir: (directory) => fsp.rm(directory, { recursive: true, force: true }),
  readText: (filename) => fsp.readFile(filename, 'utf8'),
  listFile: directory => fsp.readdir(directory),
  async access(filename) { try { await fsp.access(filename); return true; } catch { return false; } },
  moveFile: (a, b) => fsp.rename(a, b),
  unlink: filename => fsp.unlink(filename),
  fsync: fd => handles.get(fd).sync()
};
const values = new Map();
const favorites = new Set();
const readingIds = new Set();
const historyIds = new Set();
const preference = {
  async getFavorites() { return [...favorites]; },
  async getHistory() { return [...historyIds].map(bookId => ({ bookId })); },
  async getCachedBooks() { return '[]'; },
  async getImportedBooks() { return values.get('books') || '[]'; },
  async saveImportedBooks(json) { values.set('books', json); }
};
const modules = new Map();
const decodedImages = [];
let liveImages = 0;
const image = {
  createImageSource(input) {
    liveImages++;
    const bytes = Buffer.from(input);
    return {
      async getImageInfo() {
        if (!bytes.equals(MOBI_COVER_PNG)) throw new Error('invalid image');
        return { size: { width: 60, height: 90 } };
      },
      async createPixelMap(options) {
        decodedImages.push(bytes); liveImages++;
        assert.equal(options.desiredSize.width, 60);
        return { release: async () => { liveImages--; } };
      },
      release: async () => { liveImages--; }
    };
  },
  createImagePacker() {
    liveImages++;
    return {
      async packToData(_pixels, options) {
        assert.equal(options.format, 'image/jpeg');
        return Uint8Array.from([0xff, 0xd8, 0xff, 0xd9]).buffer;
      },
      release: async () => { liveImages--; }
    };
  }
};
function load(relative) {
  const filename = path.resolve(root, relative.endsWith('.ets') ? relative : relative + '.ets');
  if (modules.has(filename)) return modules.get(filename);
  const exports = {}; modules.set(filename, exports);
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInNewContext(code, { exports, console, Error, ArrayBuffer, Uint8Array, setTimeout, require: name => {
    if (name === '@kit.CoreFileKit') return { fileIo, statfs: { getFreeSize: async () => free } };
    if (name === '@kit.ImageKit') return { image };
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
    if (name.endsWith('/TextReadingProgressService')) return { TextReadingProgressService: {
      async getAll() { return [...readingIds].map(bookId => ({ bookId })); }
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
  await data.addImportedBook(epub); // Existing imported_toc must not block a second import.
  assert.equal((await data.getImportedBooks()).length, 2);
  assert.equal(epub.title, 'EPUB 标题');
  assert.equal(epub.chapters.map(ch => ch.title).join(','), '第一章,第二章');
  assert.equal(await fsp.readFile(epub.chapters[1].source.value, 'utf8'), '章节 2');

  assert.ok(service.TEXT_EXTS.includes('.mobi'), 'ZIP collection uses the same supported extensions');
  assert.ok(strings.get('import_file_filter').includes('.mobi'), 'Document picker exposes MOBI');
  file.ext = '.mobi';
  for (const compression of [1, 2]) {
    await fsp.writeFile(file.uri, mobiFixture({ compression }));
    const preview = await service.preview(context, file);
    assert.equal(preview.title, 'MOBI 测试书');
    assert.equal(preview.author, '测试作者');
    const mobi = await service.importBook(context, file, `import_mobi_${compression}`, '', '', '', () => {});
    assert.equal(mobi.title, preview.title);
    assert.equal(mobi.author, preview.author);
    assert.equal(mobi.chapters.map(ch => ch.title).join(','), '第一章 初见,第二章 重逢');
    assert.equal(await fsp.readFile(mobi.chapters[0].source.value, 'utf8'), '第一章 初见\n\n中文😀 & 正文');
    await data.addImportedBook(mobi);
    data.cache = null;
    const restoredMobi = await data.getBookById(context, mobi.id);
    assert.equal(await data.readImportedText(restoredMobi, restoredMobi.chapters[1].source.value),
      '第二章 重逢\n\n第二章内容');
    await data.removeImportedBook(mobi.id);
    assert.equal(fs.existsSync(path.join(temp, 'ebooks', mobi.id)), false);
  }
  // All PalmDOC opcodes: literals, overlapping LZ backrefs, space+char, binary literal runs.
  const opcodes = Buffer.from([0x61, 0x62, 0x63, 0x80, 0x1b, 0xd8, 3, 0xe4, 0xb8, 0xad]);
  await fsp.writeFile(file.uri, mobiFixture({ bytes: Buffer.from('abcabcabc X中'), records: [opcodes] }));
  const compressedMobi = await service.importBook(context, file, 'import_mobi_opcodes', '自定义书名', '自定义作者', '', () => {});
  assert.equal(compressedMobi.title, '自定义书名');
  assert.equal(compressedMobi.author, '自定义作者');
  assert.equal(await fsp.readFile(compressedMobi.chapters[0].source.value, 'utf8'), 'abcabcabc X中');

  // Trailing extra-data and multibyte overlap must be removed before decoding.
  await fsp.writeFile(file.uri, mobiFixture({ bytes: Buffer.from('ABC'), compression: 1, flags: 3,
    records: [Buffer.from([65, 66, 67, 0, 0, 0x82])], extraRecords: [Buffer.from('BOUNDARY'), Buffer.from('KF8')] }));
  const hybrid = await service.importBook(context, file, 'import_mobi_hybrid', '', '', '', () => {});
  assert.equal(await fsp.readFile(hybrid.chapters[0].source.value, 'utf8'), 'ABC');
  await fsp.writeFile(file.uri, mobiFixture({ bytes: Buffer.from([0x63, 0x61, 0x66, 0xe9]), compression: 1, encoding: 1252 }));
  const western = await service.importBook(context, file, 'import_mobi_1252', '', '', '', () => {});
  assert.equal(await fsp.readFile(western.chapters[0].source.value, 'utf8'), 'café');

  const invalidTable = mobiFixture(); invalidTable.writeUInt32BE(1, 86);
  const overLimit = mobiFixture(); overLimit.writeUInt32BE(33 * 1024 ** 2, overLimit.readUInt32BE(78) + 4);
  const badExth = mobiFixture(); badExth.writeUInt32BE(0xffffffff, badExth.readUInt32BE(78) + 248 + 4);
  for (const [bytes, message] of [
    [mobiFixture({ encryption: 1 }), /加密/],
    [mobiFixture({ version: 8 }), /KF8/],
    [mobiFixture({ compression: 17480 }), /HUFF/],
    [mobiFixture({ encoding: 936 }), /字符编码/],
    [mobiFixture().subarray(0, 50), /损坏/],
    [invalidTable, /损坏/], [badExth, /损坏/], [overLimit, /32 MiB/],
    [mobiFixture({ bytes: Buffer.from('test'), records: [Buffer.from([0x80, 0])] }), /损坏/],
    [mobiFixture({ bytes: Buffer.from('test'), records: [Buffer.from([8, 65])] }), /损坏/],
    [mobiFixture({ bytes: Buffer.from('test'), compression: 1, records: [Buffer.from('a')] }), /损坏/],
    [mobiFixture({ bytes: Buffer.from('test'), compression: 1, flags: 2, records: [Buffer.from([0])] }), /损坏/]
  ]) {
    await fsp.writeFile(file.uri, bytes);
    await assert.rejects(() => service.importBook(context, file, 'import_bad_mobi', '', '', '', () => {}), message);
    assert.equal(fs.existsSync(path.join(temp, 'ebooks/import_bad_mobi')), false);
    assert.equal(handles.size, 0);
  }
  console.log('PASS MOBI: metadata, uncompressed/PalmDOC, Chinese/emoji, chapters, persistence, trailing records, CP1252, rejection/cleanup');

  // The EXTH cover offset is relative to the first image record, not the file or text record list.
  for (const options of [
    { images: [Buffer.from('not a cover'), MOBI_COVER_PNG], coverOffset: 1 },
    { images: [Buffer.from('broken cover'), MOBI_COVER_PNG], coverOffset: 0, thumbnailOffset: 1 },
    { images: [MOBI_COVER_PNG] } // Legacy MOBI without EXTH cover index.
  ]) {
    await fsp.writeFile(file.uri, mobiFixture(options));
    const preview = await service.preview(context, file);
    assert.ok(preview.cover.endsWith('/cover.jpg'));
    const result = await service.importBook(context, file, 'import_mobi_cover', '', '', preview.cover, () => {});
    assert.equal(result.cover, context.filesDir + '/ebooks/import_mobi_cover/cover.jpg');
    await fsp.rm(preview.directory, { recursive: true });
    assert.ok(fs.existsSync(result.cover), 'saved cover survives preview cleanup');
    await data.addImportedBook(result);
    data.cache = null;
    assert.equal((await data.getBookById(context, result.id)).cover, result.cover);
    await data.removeImportedBook(result.id);
    assert.equal(fs.existsSync(result.cover), false);
    assert.equal(liveImages, 0);
  }
  await fsp.writeFile(file.uri, mobiFixture({ cover: true }));
  const directMobi = await service.importBook(context, file, 'import_mobi_direct_cover', '', '', '', () => {});
  assert.ok(fs.existsSync(directMobi.cover), 'ZIP imports extract a cover even without preview');
  const manualCover = path.join(temp, 'manual.jpg');
  await fsp.writeFile(manualCover, 'manual cover');
  const beforeManual = decodedImages.length;
  const manualMobi = await service.importBook(context, file, 'import_mobi_manual_cover', '', '', manualCover, () => {});
  assert.equal(await fsp.readFile(manualMobi.cover, 'utf8'), 'manual cover');
  assert.equal(decodedImages.length, beforeManual, 'user selected cover is not replaced');
  for (const options of [
    { images: [MOBI_COVER_PNG], coverOffset: 99999 },
    { images: [Buffer.from('bad image')], coverOffset: 0 },
    { images: [MOBI_COVER_PNG], firstImage: 1, coverOffset: 0 }
  ]) {
    await fsp.writeFile(file.uri, mobiFixture(options));
    const preview = await service.preview(context, file);
    assert.equal(preview.cover, '');
    assert.equal(preview.directory, '', 'empty preview directories are removed');
    const result = await service.importBook(context, file, 'import_mobi_no_cover', '', '', '', () => {});
    assert.equal(result.cover, '');
    assert.ok(result.chapters.length > 0);
    await fsp.rm(path.join(temp, 'ebooks/import_mobi_no_cover'), { recursive: true });
    assert.equal(liveImages, 0);
  }
  console.log('PASS MOBI covers: EXTH index, thumbnail/legacy fallback, direct ZIP import, persisted cover, manual override, corrupt image isolation');

  const online = { ...book, id: 'search_text_history', sourceUrl: 'source', bookUrl: 'book' };
  // 未收藏直接阅读的书经过进程重启后仍可按进度 id 找回完整信息。
  await data.upsertCachedBook(online);
  readingIds.add(online.id);
  await data.upsertCachedBook({ ...online, id: 'favorite' });
  favorites.add('favorite');
  await data.upsertCachedBook({ ...online, id: 'audio_history' });
  historyIds.add('audio_history');
  for (let i = 0; i < 205; i++) await data.upsertCachedBook({ ...online, id: 'temporary_' + i });
  data.cachedBooksMem = null;
  const readAgain = await data.getBookById(context, online.id);
  assert.equal(readAgain.title, online.title);
  assert.equal(readAgain.bookUrl, online.bookUrl);
  assert.equal(readAgain.chapters.length, online.chapters.length);
  assert.ok(await data.getBookById(context, 'favorite'));
  assert.ok(await data.getBookById(context, 'audio_history'));
  assert.equal(await data.getBookById(context, 'temporary_0'), undefined);
  assert.equal(data.cachedBooksMem.length, 203);
  console.log('PASS uncollected reading identity survives restart and 200-book cache eviction');

  const other = { ...online, id: 'other_source', sourceUrl: 'other' };
  await data.upsertCachedBook(other);
  const { OnlineTextContentCache: textCache } = load('service/text/OnlineTextContentCache');
  const textDirectory = path.join(context.cacheDir, 'online_text_content');
  await fsp.mkdir(textDirectory, { recursive: true });
  const keys = ['source', 'other'].map(sourceUrl => textCache.key(sourceUrl, 'book', 'chapter'));
  for (const key of keys) await fsp.writeFile(textCache.path(context, key),
    JSON.stringify({ version: 1, key, content: 'cached text' }));
  data.cachedBooksMem = null;
  const invalidatedChapters = new Map();
  const removed = await data.invalidateSourceCaches(new Set(['source']), (id, chapters) => {
    invalidatedChapters.set(id, chapters);
  });
  assert.ok(removed.includes(online.id));
  assert.equal(invalidatedChapters.get(online.id).length, online.chapters.length,
    'Disk-only chapters are provided for targeted audio cleanup before the TOC is removed');
  assert.equal(fs.existsSync(path.join(context.cacheDir, 'cached_toc', online.id + '.json')), false);
  assert.equal(await textCache.read(context, keys[0]), undefined);
  assert.equal(await textCache.read(context, keys[1]), 'cached text');
  data.cachedBooksMem = null;
  const invalidated = await data.getBookById(context, online.id);
  assert.equal(invalidated.title, online.title);
  assert.equal(invalidated.chapters.length, 0);
  assert.equal(invalidated.tocComplete, false);
  assert.equal((await data.getBookById(context, other.id)).chapters.length, other.chapters.length);
  assert.ok(favorites.has('favorite') && historyIds.has('audio_history'));
  console.log('PASS source replacement clears only its persisted TOC/context/text, retaining books and user progress');

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
