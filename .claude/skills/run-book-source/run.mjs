#!/usr/bin/env node
// run-book-source 运行器
// 用法:
//   node run.mjs <书源名/关键字|文件路径> <action> [arg]
//   action: search | detail <bookUrl> | toc <tocUrl> | content <chapterUrl> | full [关键词] | book <bookUrl>
// 书源来源: 项目根目录的 *.txt(每个一个源) + 1780478078.json / book_sources_all.json(集合)
// 示例:
//   node run.mjs 猫眼 full 深空彼岸
//   node run.mjs 福书 book https://www.fushucun.com/2021/75280.html
//   node run.mjs ./我的源.json search 斗破苍穹
import { Source } from './harness.mjs';
import fs from 'node:fs';
import path from 'node:path';

const PROJECT = process.env.LISTENBOOK_DIR || 'D:/ListenBook';
const OUT = path.join(process.cwd(), 'out');

function loadAllSources() {
  const map = new Map();
  const add = (s) => { if (s && s.bookSourceName) map.set(s.bookSourceName, s); };
  try {
    for (const f of fs.readdirSync(PROJECT)) {
      if (/\.txt$/i.test(f)) { try { add(JSON.parse(fs.readFileSync(path.join(PROJECT, f), 'utf8'))); } catch {} }
    }
  } catch {}
  for (const f of ['1780478078.json', 'book_sources_all.json', 'book_sources_valid.json']) {
    const p = path.join(PROJECT, f);
    if (fs.existsSync(p)) { try { const arr = JSON.parse(fs.readFileSync(p, 'utf8')); if (Array.isArray(arr)) arr.forEach(add); } catch {} }
  }
  return map;
}

function resolveSource(nameOrFile) {
  if (/[\\/]/.test(nameOrFile) || /\.(json|txt)$/i.test(nameOrFile)) {
    const j = JSON.parse(fs.readFileSync(nameOrFile, 'utf8'));
    return j;
  }
  const map = loadAllSources();
  if (map.has(nameOrFile)) return map.get(nameOrFile);
  // 部分匹配
  for (const [k, v] of map) if (k.includes(nameOrFile)) return v;
  console.error(`未找到书源 "${nameOrFile}"。可用书源:`);
  for (const k of map.keys()) console.error('  - ' + k);
  process.exit(2);
}

function saveOut(name, action, text) {
  try { fs.mkdirSync(OUT, { recursive: true }); } catch {}
  const safe = name.replace(/[^\w一-龥]+/g, '_').slice(0, 20);
  const f = path.join(OUT, `${safe}_${action}.txt`);
  fs.writeFileSync(f, text);
  console.error(`\n[已保存] ${f}`);
}

async function main() {
  const [, , nameOrFile, action = 'full', ...rest] = process.argv;
  if (!nameOrFile) {
    console.error('用法: node run.mjs <书源名/文件> <search|detail|toc|content|full|book> [arg]');
    const map = loadAllSources();
    console.error('可用书源:'); for (const k of map.keys()) console.error('  - ' + k);
    process.exit(1);
  }
  const json = resolveSource(nameOrFile);
  const src = new Source(json, { debug: process.env.DEBUG === '1' });
  const arg = rest.join(' ');
  const nm = json.bookSourceName;
  console.error(`书源: ${nm}  类型: ${json.bookSourceType === 1 ? '音频' : '文本'}  站点: ${json.bookSourceUrl}`);

  if (action === 'search') {
    const list = await src.search(arg || '斗破苍穹');
    console.log(JSON.stringify(list, null, 2));
    console.error(`\n[搜索] ${list.length} 条`);
  } else if (action === 'book') {
    const info = await src.bookInfo({ name: '(direct)', bookUrl: arg });
    const toc = await src.toc(info.tocUrl);
    console.error(`详情 tocUrl=${info.tocUrl}  目录=${toc.length} 章`);
    if (toc.length) { const t = await src.content(toc[0].url); console.log(`\n===== ${toc[0].name} =====\n` + t); saveOut(nm, '正文', `# ${toc[0].name}\n${toc[0].url}\n\n${t}`); }
  } else if (action === 'detail') {
    const info = await src.bookInfo({ name: '(direct)', bookUrl: arg });
    console.log(JSON.stringify(info, null, 2));
  } else if (action === 'toc') {
    const toc = await src.toc(arg);
    console.log(toc.map((c, i) => `${i + 1}. ${c.name}\t${c.url}`).join('\n'));
    console.error(`\n[目录] ${toc.length} 章`);
  } else if (action === 'content') {
    const t = await src.content(arg);
    console.log(t); saveOut(nm, '正文', t);
  } else if (action === 'full') {
    const list = await src.search(arg || '斗破苍穹');
    console.error(`搜索: ${list.length} 本`);
    list.slice(0, 5).forEach(b => console.error(`  - ${b.name} / ${b.author} / ${b.bookUrl.slice(0, 70)}`));
    if (!list.length) { console.error('无搜索结果'); return; }
    const info = await src.bookInfo(list[0]);
    const toc = await src.toc(info.tocUrl);
    console.error(`详情: ${info.name || list[0].name}  目录: ${toc.length} 章`);
    if (!toc.length) { console.error('无目录'); return; }
    const c0 = toc[Math.min(1, toc.length - 1)];
    const text = await src.content(c0.url);
    console.log(`\n===== 正文 [${c0.name}] =====\n${text.slice(0, 1500)}`);
    console.error(`\n[正文长度] ${text.length}`);
    saveOut(nm, '正文', `# ${list[0].name} - ${c0.name}\n${c0.url}\n\n${text}`);
  } else {
    console.error('未知 action: ' + action);
    process.exit(1);
  }
}
main().catch(e => { console.error('ERROR', e && e.stack || e); process.exit(1); });
