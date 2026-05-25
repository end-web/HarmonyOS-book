/**
 * 文本章节切分
 * 优先按 第X章/第X回/Chapter X 等模式拆分
 * 兜底按字符数分块
 */
export interface ChapterText {
  title: string;
  content: string;
}

const CHAPTER_REGEX = /^\s*(第\s*[一二三四五六七八九十百千万零〇\d]{1,8}\s*[章回节卷篇集部](?:\s|$)[^\n]{0,80}|Chapter\s+\d+[^\n]{0,80}|序[章言]\s*[^\n]{0,80}|楔\s*子\s*[^\n]{0,80})\s*$/i;

const CHUNK_SIZE = 3500;

export class TextSplitter {
  static split(text: string, fallbackTitle: string): ChapterText[] {
    if (!text || text.length === 0) {
      return [{ title: fallbackTitle, content: '' }];
    }

    const normalized = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    const lines = normalized.split('\n');

    const indices: number[] = [];
    const titles: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      const trimmed = lines[i].trim();
      if (trimmed.length === 0 || trimmed.length > 80) continue;
      if (CHAPTER_REGEX.test(trimmed)) {
        indices.push(i);
        titles.push(trimmed);
      }
    }

    if (indices.length >= 3) {
      const chapters: ChapterText[] = [];
      if (indices[0] > 0) {
        const intro = lines.slice(0, indices[0]).join('\n').trim();
        if (intro.length > 50) {
          chapters.push({ title: '前言', content: intro });
        }
      }
      for (let k = 0; k < indices.length; k++) {
        const start = indices[k];
        const end = k + 1 < indices.length ? indices[k + 1] : lines.length;
        const content = lines.slice(start + 1, end).join('\n').trim();
        chapters.push({ title: titles[k], content });
      }
      return chapters;
    }

    // 兜底分块
    return TextSplitter.chunkByChars(normalized, fallbackTitle);
  }

  private static chunkByChars(text: string, fallbackTitle: string): ChapterText[] {
    const chapters: ChapterText[] = [];
    let i = 0;
    let idx = 1;
    while (i < text.length) {
      let end = Math.min(i + CHUNK_SIZE, text.length);
      // 尝试在自然段断点处切分
      if (end < text.length) {
        const nextBreak = text.indexOf('\n', end);
        if (nextBreak >= 0 && nextBreak - end < 500) {
          end = nextBreak;
        }
      }
      const content = text.substring(i, end).trim();
      if (content.length > 0) {
        chapters.push({ title: `${fallbackTitle} ${idx}`, content });
        idx++;
      }
      i = end;
    }
    if (chapters.length === 0) {
      chapters.push({ title: fallbackTitle, content: text });
    }
    return chapters;
  }
}
