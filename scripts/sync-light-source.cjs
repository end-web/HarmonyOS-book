// Import the source engine only. UI, account, database and app configuration stay local.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const project = path.resolve(__dirname, '..');
const source = path.resolve(process.argv[2] || 'D:/legado-harmony');
const sourceRoot = path.join(source, 'entry/src/main/ets');
const engineRoot = path.join(source, 'sourceengine/src/main/ets');
const sourceRoots = [sourceRoot, engineRoot];
const exportOwners = new Map();
const packageIndex = path.join(source, 'sourceengine/Index.ts');
if (fs.existsSync(packageIndex)) {
  const index = fs.readFileSync(packageIndex, 'utf8');
  for (const match of index.matchAll(/export\s*\{([^}]+)\}\s*from\s*['"]\.\/src\/main\/ets\/([^'"]+)['"]/g)) {
    for (const name of match[1].split(',').map(value => value.trim()).filter(Boolean)) {
      if (exportOwners.has(name)) throw new Error(`Duplicate sourceengine export: ${name}`);
      exportOwners.set(name, match[2]);
    }
  }
}
const locate = name => sourceRoots.map(root => path.join(root, name)).find(fs.existsSync);
function rewritePackageImports(name, text) {
  return text.replace(/\b(import|export)\s*\{([^}]+)\}\s*from\s*['"]@legado\/sourceengine['"];?/g,
    (all, keyword, members) => {
      const groups = new Map();
      for (const member of members.split(',').map(value => value.trim()).filter(Boolean)) {
        const symbol = member.split(/\s+as\s+/)[0];
        const owner = exportOwners.get(symbol);
        if (!owner) throw new Error(`Unknown sourceengine export ${symbol} in ${name}`);
        if (!groups.has(owner)) groups.set(owner, []);
        groups.get(owner).push(member);
      }
      return [...groups].map(([owner, symbols]) => {
        let relative = path.posix.relative(path.posix.dirname(name), owner);
        if (!relative.startsWith('.')) relative = './' + relative;
        return `${keyword} { ${symbols.join(', ')} } from '${relative}';`;
      }).join('\n');
    });
}
const target = path.join(project, 'entry/src/main/ets/service/rulesource/light/upstream');
const manifestPath = path.join(project, 'third_party/light-source/upstream.json');
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const excluded = new Set(['model/data/AppDatabase.ts']);
const seeds = ['core/book/WebBookService.ts', 'core/book/SearchCoordinator.ts',
  'core/book/ExploreCoordinator.ts', 'core/nativesource/NativeSourceService.ts',
  'core/book/ReaderInteractionProvider.ts', 'core/book/BookSourceScriptRunner.ts',
  'core/book/BookSourceLoginWebRuntime.ts', 'core/http/RawHttpTextClient.ts'];
const files = new Map();
const visit = name => {
  if (files.has(name) || excluded.has(name)) return;
  const filename = locate(name);
  if (!filename) throw new Error(`Missing upstream module: ${name}`);
  const text = fs.readFileSync(filename, 'utf8');
  files.set(name, text);
  for (const match of rewritePackageImports(name, text).matchAll(/(?:from\s*|import\s*)['"]([^'"]+)['"]/g)) {
    if (match[1].startsWith('@legado/sourceengine')) throw new Error(`Unsupported package import: ${match[1]}`);
    if (!match[1].startsWith('.')) continue;
    const base = path.posix.normalize(path.posix.join(path.posix.dirname(name), match[1]));
    const found = ['.ts', '.ets', '/index.ts', '/index.ets'].map(ext => base + ext).find(locate);
    if (!found) throw new Error(`Unresolved dependency ${name}: ${match[1]}`);
    const relative = found;
    if (relative.endsWith('.ets')) throw new Error(`UI dependency must be adapted explicitly: ${relative}`);
    visit(relative);
  }
};
seeds.forEach(visit);
const previous = fs.existsSync(manifestPath) ? JSON.parse(fs.readFileSync(manifestPath, 'utf8')) : null;
for (const entry of previous?.files || []) {
  const filename = path.join(target, entry.path);
  if (!fs.existsSync(filename) || hash(fs.readFileSync(filename)) !== entry.sha256) {
    throw new Error(`Local engine change: ${entry.path}. Update the adapter/patch before syncing.`);
  }
}
const replaceMethod = (text, signature, body) => {
  const expression = new RegExp('(^  ' + signature + '[\\s\\S]*?\\n  \\})', 'm');
  if (!expression.test(text)) throw new Error(`Upstream method changed: ${signature}`);
  return text.replace(expression, body);
};
function adapt(name, text) {
  // Shared host ports carry execution policy. Synchronization only rewrites module paths.
  return rewritePackageImports(name, text).replaceAll('\r\n', '\n');
}

// Prepare and validate every transformation before mutating the working tree.
const generated = [...files].map(([name, original]) => ({ name, original, text: adapt(name, original) }));
// Keep upstream CookieStore semantics reusable, while its persistence/session entry remains local.
const cookieOriginal = files.get('core/http/CookieStore.ts');
let cookieSemantics = cookieOriginal.replaceAll('CookieStore', 'LightCookieSemantics')
    .replace('fetchCookieSync(target)', 'fetchCookieSync(target, true)')
    .replaceAll('configCookieSync(target, value, false, true)', 'configCookieSync(target, value, true, true)')
    .replaceAll('configCookieSync(target, value)', 'configCookieSync(target, value, true)')
    .replace('clearAllCookiesSync()', 'clearAllCookiesSync(true)')
    .replace('private static withoutExpiredJwtCookies', 'static withoutExpiredJwtCookies');
cookieSemantics = replaceMethod(cookieSemantics, 'static saveAsync\\(',
  '  static saveAsync(): void { /* Encrypted persistence is flushed by the source lease. */ }');
generated.push({name:'core/http/LightCookieSemantics.ts',original:cookieOriginal,text:cookieSemantics});
const page = fs.readFileSync(path.join(sourceRoot, 'pages/BookSource.ets'), 'utf8').replaceAll('\r\n', '\n');
const methods = ['parseBookSource', 'parseCompactRule', 'applyRuleToSearchRule', 'applyRuleToTocRule',
  'applyRuleToContentRule', 'applyRuleToBookInfoRule'].map(name => {
  const match = page.match(new RegExp('^  ' + name + '\\([\\s\\S]*?\\n  \\}', 'm'));
  if (!match) throw new Error(`Source import method changed: ${name}`);
  return match[0];
});
generated.push({ name: 'LightSourceImport.ts', original: methods.join('\n'), text:
  `import { BookSource, SearchRule, ExploreRule, BookInfoRule, TocRule, ContentRule } from './model/data/Book';\n` +
  `export class LightSourceImport {\n${methods.join('\n\n')}\n}\n` });
// The package now provides a platform-free import entry; keep the existing application alias.
generated.push({ name: 'LightNativeImport.ts', original: files.get('core/nativesource/NativeSourceImport.ts'),
  text: "export { NativeSourceImport as NativeSourceService } from './core/nativesource/NativeSourceImport';\n" });
// The upstream audio page performs a second parsing step after the rule engine:
// unwrap JSON/HTML media results and carry the source's scoped stream headers.
// Extract those methods verbatim so adapter behavior follows the pinned player.
const audioPage = fs.readFileSync(path.join(sourceRoot, 'pages/AudioBook.ets'), 'utf8').replaceAll('\r\n', '\n');
const audioMethods = ['resolveAudioUrl', 'audioUrlFromObject', 'invalidAudioAddressMessage',
  'decodeAudioRuleValue', 'normalizeAudioCandidate', 'audioHeaders', 'sourceAudioHeaders'].map(name => {
  const match = audioPage.match(new RegExp('^  (?:private )?' + name + '\\([\\s\\S]*?\\n  \\}', 'm'));
  if (!match) throw new Error(`Source audio method changed: ${name}`);
  return match[0];
});
generated.push({ name: 'LightAudioSupport.ts', original: audioMethods.join('\n'), text:
  `import { BookSource } from './model/data/Book';\n` +
  `import { AudioRuleSupport } from './core/book/AudioRuleSupport';\n` +
  `import { BookUrlResolver } from './core/book/BookUrlResolver';\n` +
  `import { VerificationSupport } from './core/http/VerificationSupport';\n` +
  `export class LightAudioSupport {\n${audioMethods.join('\n\n')}\n}\n` });
const commit = cp.execFileSync('git', ['-C', source, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
const status = cp.execFileSync('git', ['-C', source, 'status', '--porcelain', '--', 'entry/src/main/ets', 'sourceengine', 'LICENSE'], { encoding: 'utf8' }).trim();
if (status) throw new Error('The upstream source working tree must be clean.');
for (const entry of previous?.files || []) {
  if (!generated.some(value => value.name === entry.path)) fs.unlinkSync(path.join(target, entry.path));
}
for (const entry of generated) {
  const filename = path.join(target, entry.name);
  fs.mkdirSync(path.dirname(filename), { recursive: true });
  fs.writeFileSync(filename, entry.text);
}
const licenseDir = path.dirname(manifestPath);
fs.mkdirSync(licenseDir, { recursive: true });
fs.copyFileSync(path.join(source, 'LICENSE'), path.join(licenseDir, 'LICENSE'));
const packagedLicense = path.join(project, 'entry/src/main/resources/rawfile/third_party/light-source/LICENSE');
fs.mkdirSync(path.dirname(packagedLicense), {recursive:true});
fs.copyFileSync(path.join(source, 'LICENSE'), packagedLicense);
fs.writeFileSync(manifestPath, JSON.stringify({ repository: 'https://github.com/wip3l/legado-harmony',
  fork: 'https://github.com/hos-book/legado-harmony', commit, license: 'GPL-3.0',
  files: generated.map(entry => ({ path: entry.name,
    ...(locate(entry.name) ? { upstreamPath: path.relative(source, locate(entry.name)).replaceAll('\\', '/') } : {}),
    upstreamSha256: hash(entry.original), sha256: hash(entry.text) }))
}, null, 2) + '\n');
console.log(`Imported ${generated.length} source-engine files at ${commit}. No pages copied.`);
