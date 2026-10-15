import { Chapter } from '../model/Book';
import { ChapterCacheCodec } from './ChapterCacheCodec';

/** 大目录 JSON 在后台解析，避免文件读取完成回调连续占用 UI 线程。 */
@Concurrent
export function parseCachedChapters(json: string): Chapter[] {
  const chapters: Chapter[] = ChapterCacheCodec.parse(json);
  return chapters;
}
