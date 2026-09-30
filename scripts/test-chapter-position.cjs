// Run the actual shared resolver against duplicate titles and changed catalogs.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const filename = path.resolve(__dirname, '../entry/src/main/ets/service/DataService.ets');
const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
const exportsObject = {};
vm.runInNewContext(output, { exports: exportsObject, require: () => ({}) }, { filename });
const resolve = exportsObject.DataService.resolveChapterIndex;
const book = { chapters: ['序章', '重逢', '过渡', '重逢', '终章'].map((title, i) => ({
  id: `book-c${i}`, index: i + 1, title
})) };
assert.equal(resolve(book, 'book-c3', '重逢'), 3, 'later duplicate keeps its own position');
assert.equal(resolve(book, 'book-c1', '重逢'), 1, 'earlier duplicate keeps its own position');
assert.equal(resolve(book, 'book-c2', '重逢'), 2, 'ambiguous title cannot override saved position');
assert.equal(resolve(book, 'missing', '重逢'), -1, 'ambiguous title alone cannot select the first chapter');
assert.equal(resolve(book, 'book-c3', '终章'), 4, 'unique title repairs a shifted positional ID');
assert.equal(resolve(book, 'missing', '终章'), 4, 'unique title supports legacy IDs');
assert.equal(resolve(book, 'book-c3'), 3, 'old records without titles still restore');
assert.equal(resolve(book, 'book-c3', '改名前'), 3, 'renamed chapter retains its position');
assert.equal(resolve(book, '', ''), -1);
assert.equal(resolve({ chapters: [] }, 'book-c3', '重逢'), -1);
book.chapters.reverse();
assert.equal(resolve(book, 'book-c3', '重逢'), 1, 'display reordering retains chapter identity');
console.log('Chapter position regression: 11 checks passed');
