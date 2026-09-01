/**
 * 听书源与页面之间的最小数据契约。
 *
 * 在线内容只由内置音频源提供，因此这里不再携带 Legado 规则、登录或订阅字段。
 */
export interface BookSource {
  bookSourceUrl: string;
  bookSourceName: string;
  /** 可选来源类型：0/3=文本，1=音频，2=漫画；现有内置源不填写时按音频处理。 */
  bookSourceType?: number;
  /** 是否参与聚合搜索；详情、目录和正文解析不受此字段限制。 */
  enabled?: boolean;
}

export interface SearchResult {
  name: string;
  author: string;
  coverUrl: string;
  bookUrl: string;
  intro: string;
  kind: string;
  /** 单条结果的内容类型；聚合源可覆盖书源级默认类型。 */
  contentType?: 'audio' | 'text';
  /** 是否完结（源端 status=1） */
  completed?: boolean;
  lastChapter: string;
  wordCount?: string;
  sourceName: string;
  sourceUrl: string;
  variables?: Record<string, string>;
}

export interface TocItem {
  name: string;
  url: string;
  isVip?: boolean;
  isPay?: boolean;
  isVolume?: boolean;
  updateTime?: string;
  duration?: number;
  /** 目录元素独立产生的 @put/脚本变量，供该章节后续正文或音频解析使用。 */
  variables?: Record<string, string>;
}

export interface BookInfo {
  name: string;
  author: string;
  coverUrl: string;
  intro: string;
  kind: string;
  /** 是否完结 */
  completed?: boolean;
  wordCount: string;
  lastChapter: string;
  tocUrl: string;
  variables?: Record<string, string>;
}

export interface HomeBlockSection {
  title: string;
  books: SearchResult[];
  moreUrl: string;
  layout: string;
  sourceName: string;
  sourceUrl: string;
}
