import { TocItem } from '../../../model/BookSource';
import { KkBiqugeHtmlParser } from '../../text/KkBiqugeHtmlParser';
import { LocalRuleUrlAnalyzer } from '../LocalRuleUrlAnalyzer';
import { TalebookApiClient } from './TalebookApiClient';

class TalebookEpubItem {
  id: string = '';
  href: string = '';
  mediaType: string = '';
  properties: string = '';
}

/** 只读取 NAS 已解包的 EPUB；不执行书内脚本，不请求外部资源。 */
export class TalebookEpub {
  static attribute(tag: string, name: string): string {
    const found = new RegExp('(?:^|\\s)' + name + '\\s*=\\s*["\']([^"\']*)["\']', 'i').exec(tag);
    return found ? KkBiqugeHtmlParser.cleanText(found[1]) : '';
  }

  static resource(root: string, base: string, href: string): string {
    const address = LocalRuleUrlAnalyzer.resolveUrl(base, href).split('#')[0];
    const decoded = decodeURIComponent(address);
    if (!address.startsWith(root) || !decoded.startsWith(root) ||
      new RegExp('(?:^|/)\\.\\.(?:/|$)|\\\\').test(decoded) || address.includes('?')) {
      throw new Error('EPUB 包含越界资源路径');
    }
    return address;
  }

  static parseSpine(opf: string, root: string, opfUrl: string,
    labels: Map<string, string> = new Map<string, string>()): TocItem[] {
    const items = TalebookEpub.items(opf);
    const byId = new Map<string, TalebookEpubItem>();
    for (const item of items) byId.set(item.id, item);
    const refs = opf.match(new RegExp('<(?:[\\w-]+:)?itemref\\b[^>]*>', 'gi')) ?? [];
    const result: TocItem[] = [];
    const seen = new Set<string>();
    for (const ref of refs.slice(0, 20000)) {
      if (TalebookEpub.attribute(ref, 'linear') === 'no') continue;
      const item = byId.get(TalebookEpub.attribute(ref, 'idref'));
      if (!item || !['application/xhtml+xml', 'text/html'].includes(item.mediaType)) continue;
      const address = TalebookEpub.resource(root, opfUrl, item.href);
      if (seen.has(address)) continue;
      seen.add(address);
      const chapter: TocItem = {
        name: labels.get(address) || `第 ${result.length + 1} 节`, url: address
      };
      result.push(chapter);
    }
    if (result.length === 0) throw new Error('EPUB 没有可读取的文字章节');
    return result;
  }

  static items(opf: string): TalebookEpubItem[] {
    const result: TalebookEpubItem[] = [];
    const tags = opf.replace(new RegExp('<!--[\\s\\S]*?-->', 'g'), '')
      .match(new RegExp('<(?:[\\w-]+:)?item\\b[^>]*>', 'gi')) ?? [];
    if (tags.length > 20000) throw new Error('EPUB 资源数量超过限制');
    for (const tag of tags) {
      const item = new TalebookEpubItem();
      item.id = TalebookEpub.attribute(tag, 'id');
      item.href = TalebookEpub.attribute(tag, 'href');
      item.mediaType = TalebookEpub.attribute(tag, 'media-type');
      item.properties = TalebookEpub.attribute(tag, 'properties');
      if (item.id && item.href) result.push(item);
    }
    return result;
  }

  static async toc(sourceUrl: string, id: number): Promise<TocItem[]> {
    const root = TalebookApiClient.address(sourceUrl, `/get/extract/${id}/`);
    const container = await TalebookApiClient.request(sourceUrl, `${root}META-INF/container.xml`, false);
    const rootfile = new RegExp('<(?:[\\w-]+:)?rootfile\\b[^>]*>', 'i').exec(container);
    const path = rootfile ? TalebookEpub.attribute(rootfile[0], 'full-path') : '';
    if (!path) throw new Error('EPUB 尚未准备好，或缺少 container.xml，请稍后重试');
    const opfUrl = TalebookEpub.resource(root, root, path);
    const opf = await TalebookApiClient.request(sourceUrl, opfUrl, false);
    const labels = new Map<string, string>();
    const navigation = TalebookEpub.items(opf).find((item: TalebookEpubItem): boolean =>
      item.mediaType === 'application/x-dtbncx+xml' || item.properties.split(' ').includes('nav'));
    if (navigation) {
      try {
        const navUrl = TalebookEpub.resource(root, opfUrl, navigation.href);
        const nav = await TalebookApiClient.request(sourceUrl, navUrl, false);
        const pattern = navigation.mediaType === 'application/x-dtbncx+xml'
          ? new RegExp('<(?:[\\w-]+:)?navLabel\\b[^>]*>[\\s\\S]*?<text\\b[^>]*>([\\s\\S]*?)</text>[\\s\\S]*?</(?:[\\w-]+:)?navLabel>\\s*<content\\b([^>]*)>', 'gi')
          : new RegExp('<a\\b([^>]*)>([\\s\\S]*?)</a>', 'gi');
        let match = pattern.exec(nav);
        while (match !== null && labels.size < 20000) {
          const ncx = navigation.mediaType === 'application/x-dtbncx+xml';
          const href = TalebookEpub.attribute(ncx ? match[2] : match[1], ncx ? 'src' : 'href');
          const label = KkBiqugeHtmlParser.cleanText(ncx ? match[1] : match[2]);
          if (href && label) {
            const url = TalebookEpub.resource(root, navUrl, href);
            if (!labels.has(url)) labels.set(url, label);
          }
          match = pattern.exec(nav);
        }
      } catch (_error) {
        // 目录标题是可选的；仍按 EPUB spine 顺序读取全部文字资源。
      }
    }
    return TalebookEpub.parseSpine(opf, root, opfUrl, labels);
  }

  static content(html: string): string {
    const body = new RegExp('<body\\b[^>]*>([\\s\\S]*?)</body>', 'i').exec(html);
    if (!body) throw new Error('Talebook 未返回有效的 EPUB 正文');
    const text = KkBiqugeHtmlParser.cleanContent(body[1]);
    return text || '本节没有文字内容。';
  }
}
