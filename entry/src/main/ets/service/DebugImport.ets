/**
 * DebugImport - 临时调试用：启动时自动导入 rawfile 里的测试书源（福书 / 猫眼）。
 * 仅用于真机验证电子书源 + 阅读器链路，验证完可整体删除（含 EntryAbility 里的一行调用 + rawfile）。
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { BookSource } from '../model/BookSource';
import { BookSourceService } from './BookSourceService';
import { SourceDataService } from './SourceDataService';

const DBG = 0x9527;
const DT = 'DbgImport';

async function readRawJson(context: common.UIAbilityContext, name: string): Promise<string> {
  const bytes = await context.resourceManager.getRawFileContent(name);
  return util.TextDecoder.create('utf-8').decodeToString(bytes);
}

export async function autoImportDebugSources(context: common.UIAbilityContext): Promise<void> {
  try {
    // 移除旧的 legado 猫眼/福书 —— 已分别由内置源 Maoyan.ets / Fushu.ets 取代（只删非内置的）
    try {
      const cur = await SourceDataService.getSources();
      for (const s of cur) {
        const u = s ? s.bookSourceUrl : '';
        if (typeof u === 'string' && !u.startsWith('builtin://') &&
            (u.indexOf('yichnmedia') >= 0 || u.indexOf('fushucun') >= 0)) {
          await SourceDataService.removeSource(u);
          hilog.info(DBG, DT, 'removed legado dup: %{public}s', s.bookSourceName);
        }
      }
    } catch (e) { /* ignore */ }

    const existing = await SourceDataService.getSources();
    const have = new Set<string>();
    for (const s of existing) have.add(s.bookSourceUrl);

    // 猫眼/福书均改用内置源，这里不再导入 dbg_*.json
    const files: string[] = [];
    const toAdd: BookSource[] = [];
    for (const f of files) {
      try {
        const json = await readRawJson(context, f);
        const parsed = BookSourceService.parseSourcesFromJson(json);
        hilog.info(DBG, DT, '%{public}s parsed=%{public}d', f, parsed.length);
        for (const s of parsed) {
          if (s && s.bookSourceUrl && !have.has(s.bookSourceUrl)) {
            toAdd.push(s);
            have.add(s.bookSourceUrl);
            hilog.info(DBG, DT, 'queue add: name=%{public}s url=%{public}s', s.bookSourceName, s.bookSourceUrl);
          }
        }
      } catch (e) {
        hilog.error(DBG, DT, 'read/parse %{public}s failed=%{public}s', f, (e as Error).message ?? JSON.stringify(e));
      }
    }
    if (toAdd.length > 0) {
      await SourceDataService.addSources(toAdd);
      hilog.info(DBG, DT, 'added %{public}d sources', toAdd.length);
    } else {
      hilog.info(DBG, DT, 'no new sources (already imported)');
    }
  } catch (e) {
    hilog.error(DBG, DT, 'autoImport failed=%{public}s', (e as Error).message ?? JSON.stringify(e));
  }
}

/** [DEBUG] 完整管线自测:对 福书/猫眼 各自 search→bookInfo→toc→content,打印每步结果(尤其正文长度+开头) */
export async function debugSourcePipelineTest(keyword: string): Promise<void> {
  const TS = 'DbgPipe';
  try {
    const sources = await SourceDataService.getSources();
    const targets = sources.filter((s: BookSource): boolean =>
      s.bookSourceUrl.indexOf('fushucun') >= 0 || s.bookSourceUrl.indexOf('yichnmedia') >= 0 ||
      s.bookSourceUrl.indexOf('suixkan') >= 0);
    hilog.info(DBG, TS, 'pipeline start kw=%{public}s targets=%{public}d', keyword, targets.length);
    for (const s of targets) {
      try {
        const res = await BookSourceService.searchBooks(s, keyword, 1);
        hilog.info(DBG, TS, '[%{public}s] 1.search=%{public}d', s.bookSourceName, res.length);
        if (res.length === 0) continue;
        const first = res[0];
        hilog.info(DBG, TS, '[%{public}s] book=%{public}s url=%{public}s', s.bookSourceName, first.name, first.bookUrl);
        const info = await BookSourceService.getBookInfo(s, first.bookUrl, first.variables);
        const tocUrl = (info && info.tocUrl) ? info.tocUrl : first.bookUrl;
        const vars: Record<string, string> = {};
        const toc = await BookSourceService.getBookToc(s, tocUrl, vars, first.name);
        hilog.info(DBG, TS, '[%{public}s] 2.toc=%{public}d firstCh=%{public}s', s.bookSourceName, toc.length, toc.length > 0 ? toc[0].name : '');
        if (toc.length === 0) continue;
        const content = await BookSourceService.getTextContent(s, toc[0].url);
        hilog.info(DBG, TS, '[%{public}s] 3.contentLen=%{public}d head=%{public}s', s.bookSourceName, content.length, content.substring(0, 200));
      } catch (e) {
        hilog.error(DBG, TS, '[%{public}s] FAILED=%{public}s', s.bookSourceName, (e as Error).message ?? JSON.stringify(e));
      }
    }
    hilog.info(DBG, TS, 'pipeline done');
  } catch (e) {
    hilog.error(DBG, TS, 'pipeline fatal=%{public}s', (e as Error).message ?? JSON.stringify(e));
  }
}

/** [DEBUG] 直连自测:对 福书/猫眼/笔趣 各自调 searchBooks,打印条数/首条/耗时/报错 */
export async function debugSearchSelfTest(keyword: string): Promise<void> {
  const TS = 'DbgSearch';
  try {
    const sources = await SourceDataService.getSources();
    const targets = sources.filter((s: BookSource): boolean =>
      s.bookSourceUrl.indexOf('fushucun') >= 0 ||
      s.bookSourceUrl.indexOf('yichnmedia') >= 0 ||
      s.bookSourceUrl.indexOf('biqun') >= 0);
    hilog.info(DBG, TS, 'selftest start kw=%{public}s targets=%{public}d', keyword, targets.length);
    for (const s of targets) {
      const t0 = Date.now();
      try {
        const res = await BookSourceService.searchBooks(s, keyword, 1);
        const first = res.length > 0 ? JSON.stringify(res[0]).substring(0, 160) : '';
        hilog.info(DBG, TS, '[%{public}s] count=%{public}d ms=%{public}d first=%{public}s',
          s.bookSourceName, res.length, Date.now() - t0, first);
      } catch (e) {
        hilog.error(DBG, TS, '[%{public}s] FAILED ms=%{public}d err=%{public}s',
          s.bookSourceName, Date.now() - t0, (e as Error).message ?? JSON.stringify(e));
      }
    }
    hilog.info(DBG, TS, 'selftest done');
  } catch (e) {
    hilog.error(DBG, TS, 'selftest fatal=%{public}s', (e as Error).message ?? JSON.stringify(e));
  }
}
