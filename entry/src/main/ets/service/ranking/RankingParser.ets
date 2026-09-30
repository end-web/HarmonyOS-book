import { RankingBook } from '../../model/Ranking';
import { JsonObj } from '../builtin/JsonValue';

/** 只解析已经下载的公开榜单文本，不执行页面脚本。 */
export class RankingParser {
  static text(html: string): string {
    return html.replace(/<[^>]*>/g, '').replace(/&amp;/g, '&').replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'")
      .replace(/&nbsp;|\u00a0/g, ' ').replace(/&#(\d+);/g,
        (_match: string, code: string): string => String.fromCharCode(Number(code)))
      .replace(/\s+/g, ' ').trim();
  }

  private static capture(html: string, pattern: RegExp): string {
    return RankingParser.text(pattern.exec(html)?.[1] ?? '');
  }

  static imageUrl(value: string): string {
    const clean = value.replace(/&amp;/g, '&').trim();
    if (clean.startsWith('//')) return `https:${clean}`;
    return clean.startsWith('https://') ? clean : '';
  }

  static parse(platform: string, boardId: string, body: string): RankingBook[] {
    if (!body || body.length > 2 * 1024 * 1024) return [];
    if (platform === 'ximalaya') return RankingParser.ximalaya(boardId, body);
    if (platform === 'qimao') return RankingParser.qimao(body);
    if (platform === 'jjwxc') return RankingParser.jjwxc(body);
    const blocks = platform === 'qidian'
      ? body.match(/<a\b[^>]*href="(?:https?:)?\/\/m\.qidian\.com\/book\/\d+\/"[^>]*>[\s\S]*?<\/a>/g) ?? []
      : body.match(/<li\s+class="book-item"[^>]*>[\s\S]*?<\/li>/g) ?? [];
    const books: RankingBook[] = [];
    const seen = new Set<string>();
    for (const html of blocks.slice(0, 100)) {
      const platformBookId = /\/book\/(\d+)/.exec(html)?.[1] ?? '';
      if (!platformBookId || seen.has(platformBookId)) continue;
      const book = new RankingBook();
      book.id = `${platform}:${platformBookId}`;
      book.platformId = platform;
      book.rank = books.length + 1;
      if (platform === 'qidian') {
        book.contentType = 'text';
        book.title = RankingParser.capture(html, /<h2\b[^>]*>([\s\S]*?)<\/h2>/);
        const subtitle = RankingParser.capture(html, /<p\b[^>]*class="[^"]*_subTitle_[^"]*"[^>]*>([\s\S]*?)<\/p>/);
        book.author = subtitle.split('·')[0].trim();
        book.coverUrl = RankingParser.imageUrl(/data-src="([^"]+)"/.exec(html)?.[1] ?? '')
          .replace(/(bookcover\.yuewen\.com\/qdbimg\/\d+\/\d+)\/180$/, '$1/600');
        book.originalUrl = `https://m.qidian.com/book/${platformBookId}/`;
        book.intro = RankingParser.capture(html, /<p\b[^>]*class="[^"]*_bookDesc_[^"]*"[^>]*>([\s\S]*?)<\/p>/);
      } else {
        book.contentType = 'audio';
        book.title = RankingParser.capture(html, /<a\b[^>]*class="book-item-name"[^>]*>([\s\S]*?)<\/a>/);
        book.author = RankingParser.capture(html, /<a\b[^>]*class="author"[^>]*>([\s\S]*?)<\/a>/);
        book.narrator = RankingParser.capture(html, /主播：[\s\S]*?<a\b[^>]*>([\s\S]*?)<\/a>/);
        book.coverUrl = RankingParser.imageUrl(/<img\b[^>]*\bsrc="([^"]+)"/.exec(html)?.[1] ?? '')
          .replace(/(bookpic\.lrts\.me\/[^/?]+-1-\d+)\.(png|jpg|jpeg)$/, '$1_600x600.$2');
        book.originalUrl = `https://www.lrts.me/book/${platformBookId}`;
        book.intro = RankingParser.capture(html, /<p\b[^>]*class="book-item-desc[^\"]*"[^>]*>([\s\S]*?)<\/p>/);
      }
      if (!book.title) continue;
      seen.add(platformBookId);
      books.push(book);
    }
    return books;
  }

  private static ximalaya(boardId: string, body: string): RankingBook[] {
    const root = new JsonObj(JSON.parse(body));
    if (root.getInt('ret') !== 200) return [];
    const list = root.getObj('data').getObj(boardId === 'xm-paid' ? 'paidAlbumRank' : 'freeAlbumRank')
      .getArr('rankListInfo');
    const books: RankingBook[] = [];
    const seen = new Set<string>();
    for (let index = 0; index < Math.min(list.length(), 100); index++) {
      const item = list.getObj(index);
      const id = item.getString('id');
      if (!/^\d+$/.test(id) || seen.has(id)) continue;
      const book = new RankingBook();
      book.id = `ximalaya:${id}`;
      book.platformId = 'ximalaya';
      book.title = RankingParser.text(item.getString('albumTitle'));
      book.narrator = RankingParser.text(item.getString('anchorName'));
      book.coverUrl = RankingParser.imageUrl(item.getString('cover'));
      book.originalUrl = `https://www.ximalaya.com/album/${id}`;
      book.contentType = 'audio';
      book.intro = RankingParser.text(item.getString('description'));
      book.rank = index + 1;
      if (!book.title) continue;
      seen.add(id);
      books.push(book);
    }
    return books;
  }

  private static qimao(body: string): RankingBook[] {
    const rows = body.match(/<li\b[^>]*class="rank-list-item"[^>]*>[\s\S]*?<\/li>/g) ?? [];
    const books: RankingBook[] = [];
    const seen = new Set<string>();
    for (const row of rows.slice(0, 100)) {
      const id = /\/shuku\/(\d+)\//.exec(row)?.[1] ?? '';
      if (!id || seen.has(id)) continue;
      const book = new RankingBook();
      book.id = `qimao:${id}`;
      book.platformId = 'qimao';
      book.title = RankingParser.capture(row, /<a\b[^>]*class="s-book-title"[^>]*>([\s\S]*?)<\/a>/);
      book.author = RankingParser.capture(row, /<a\b[^>]*href="[^\"]*\/zuozhe\/[^\"]*"[^>]*>([\s\S]*?)<\/a>/);
      book.coverUrl = RankingParser.imageUrl(/<img\b[^>]*\bsrc="([^\"]+)"/.exec(row)?.[1] ?? '');
      book.intro = RankingParser.capture(row, /<span\b[^>]*class="s-book-intro"[^>]*>([\s\S]*?)<\/span>/);
      book.originalUrl = `https://www.qimao.com/shuku/${id}/`;
      book.rank = books.length + 1;
      if (!book.title) continue;
      seen.add(id);
      books.push(book);
    }
    return books;
  }

  private static jjwxc(body: string): RankingBook[] {
    const rows = body.match(/<tr\b[^>]*>[\s\S]*?<\/tr>/g) ?? [];
    const books: RankingBook[] = [];
    const seen = new Set<string>();
    for (const row of rows) {
      if (books.length >= 100) break;
      const tags = row.match(/<a\b(?:[^"'<>]|"[^"]*"|'[^']*')*>/g) ?? [];
      const link = tags.find((tag: string): boolean => /href="onebook\.php\?novelid=\d+"/.test(tag));
      if (!link) continue;
      const id = /novelid=(\d+)/.exec(link)?.[1] ?? '';
      if (!id || seen.has(id)) continue;
      const book = new RankingBook();
      book.id = `jjwxc:${id}`;
      book.platformId = 'jjwxc';
      book.title = RankingParser.capture(link, /\btitle="([^"]+)"/);
      const authorLink = tags.find((tag: string): boolean => tag.includes('oneauthor.php?authorid='));
      book.author = RankingParser.capture(authorLink ?? '', /\btitle="([^"]+)"/);
      book.intro = RankingParser.capture(link, /\brel="([^"]*)"/);
      book.coverUrl = `https://i9-static.jjwxc.net/novelimage.php?novelid=${id}`;
      book.originalUrl = `https://www.jjwxc.net/onebook.php?novelid=${id}`;
      book.rank = books.length + 1;
      if (!book.title || !book.author) continue;
      seen.add(id);
      books.push(book);
    }
    return books;
  }
}
