import { buffer } from '@kit.ArkTS';

// 本模块只能依赖后台可用的基础库，不能导入含 @Trace/@ObservedV2 的模型或业务服务。
class ImportJsonSource {
  bookSourceName: string = '';
  bookSourceUrl: string = '';
}

class ImportJsonEnvelope extends ImportJsonSource {
  value?: ImportJsonSource[];
  data?: ImportJsonSource[];
  sources?: ImportJsonSource[];
  bookSources?: ImportJsonSource[];
  bookSourceList?: ImportJsonSource[];
  list?: ImportJsonSource[];
}

/** 返回拒绝数量和原始定义，完整模型只在主线程创建。 */
@Concurrent
export function parseImportFile(content: string): string[] {
  const entries: string[] = ['0'];
  const root: ImportJsonEnvelope = JSON.parse(content.trim());
  if (root === null || typeof root !== 'object') return entries;
  let items: ImportJsonSource[] = [];
  if (Array.isArray(root)) items = root;
  else if (Array.isArray(root.value)) items = root.value;
  else if (Array.isArray(root.data)) items = root.data;
  else if (Array.isArray(root.sources)) items = root.sources;
  else if (Array.isArray(root.bookSources)) items = root.bookSources;
  else if (Array.isArray(root.bookSourceList)) items = root.bookSourceList;
  else if (Array.isArray(root.list)) items = root.list;
  else items = [root];
  const count = Math.min(items.length, 1000);
  let rejected = items.length - count;
  for (let index = 0; index < count; index++) {
    const item = items[index];
    if (item === null || typeof item !== 'object' || Array.isArray(item)) { rejected++; continue; }
    const raw = JSON.stringify(item);
    if (buffer.byteLength(raw, 'utf-8') > 512 * 1024) { rejected++; continue; }
    entries.push(raw);
  }
  entries[0] = String(rejected);
  return entries;
}
