/**
 * 章节段落数据源，配合 LazyForEach 渲染长正文
 * key 用 chapterId+index，避免 index 单独作为 key
 */
export class ParagraphDataSource implements IDataSource {
  private paras: string[] = [];
  private chapterId: string = '';
  private listeners: DataChangeListener[] = [];

  setData(chapterId: string, paras: string[]): void {
    this.chapterId = chapterId;
    this.paras = paras;
    this.listeners.forEach((l) => l.onDataReloaded());
  }

  totalCount(): number {
    return this.paras.length;
  }

  getData(index: number): string {
    return this.paras[index];
  }

  keyOf(index: number): string {
    return `${this.chapterId}#${index}`;
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const i = this.listeners.indexOf(listener);
    if (i >= 0) this.listeners.splice(i, 1);
  }
}

const SENTENCE_ENDS = '。！？…"」』）)';
const PARA_MAX_LEN = 1500;

/**
 * 把章节正文按段落切分，兼容多种 TXT / 网络源格式
 */
export function splitParagraphs(content: string): string[] {
  if (!content) return [];

  let text = content;

  // HTML 标签转换（网络书源可能返回 <br>/<p> 等）
  text = text.replace(/<br\s*\/?>/gi, '\n');
  text = text.replace(/<\/?p[^>]*>/gi, '\n');
  text = text.replace(/&nbsp;/gi, ' ');
  text = text.replace(/<[^>]+>/g, '');

  // 统一换行符
  text = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');

  const nonEmptyLines = text.split('\n').filter((l) => l.trim().length > 0);
  let paragraphs: string[];

  if (nonEmptyLines.length <= 3 && text.length > 200) {
    // 几乎无换行 → 尝试按全角空格缩进分段（常见 TXT 格式）
    const indentSplit = text.split('　　').map((s) => s.trim()).filter((s) => s.length > 0);
    if (indentSplit.length >= 2) {
      paragraphs = indentSplit;
    } else {
      paragraphs = splitBySentence(text.trim(), 500);
    }
  } else {
    paragraphs = nonEmptyLines;
  }

  // 去除段首全角空格和普通空白（UI 层 textIndent 负责缩进）
  paragraphs = paragraphs
    .map((p) => p.replace(/^[　 \t]+/, '').trimEnd())
    .filter((p) => p.length > 0);

  // 超长段落兜底拆分
  const result: string[] = [];
  for (const para of paragraphs) {
    if (para.length <= PARA_MAX_LEN) {
      result.push(para);
    } else {
      const parts = splitBySentence(para, PARA_MAX_LEN);
      for (const part of parts) {
        result.push(part);
      }
    }
  }

  return result.length > 0 ? result : [content.trim()];
}

function splitBySentence(text: string, maxLen: number): string[] {
  const result: string[] = [];
  let current = '';

  for (let i = 0; i < text.length; i++) {
    current += text[i];
    if (current.length >= maxLen) {
      let breakIdx = -1;
      const searchStart = Math.max(0, current.length - 200);
      for (let j = current.length - 1; j >= searchStart; j--) {
        if (SENTENCE_ENDS.indexOf(current[j]) >= 0) {
          breakIdx = j;
          break;
        }
      }
      if (breakIdx > 0) {
        result.push(current.substring(0, breakIdx + 1));
        current = current.substring(breakIdx + 1);
      } else {
        result.push(current);
        current = '';
      }
    }
  }
  if (current.trim().length > 0) {
    result.push(current);
  }
  return result.length > 0 ? result : [text];
}
