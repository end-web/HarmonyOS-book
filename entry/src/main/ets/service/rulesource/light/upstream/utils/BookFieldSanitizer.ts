export class BookFieldSanitizer {
  static prefer(newValue: string, fallback: string): string {
    const cleaned = BookFieldSanitizer.clean(newValue);
    return cleaned || BookFieldSanitizer.clean(fallback);
  }

  static clean(value: string): string {
    // A combined selector + JS rule may produce useful text even when one optional template
    // expression is unsupported or absent. Remove those isolated placeholders before deciding
    // whether the whole field is unresolved; never expose the rule expression itself.
    const text = (value || '').replace(/\{\{[\s\S]*?\}\}/g, '').trim();
    if (!text || BookFieldSanitizer.isUnresolved(text)) {
      return '';
    }
    const cleaned = text
      .replace(/&nbsp;/gi, ' ')
      .replace(/&lrm;/gi, '')
      .replace(/&shy;/gi, '')
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<[^>]+>/g, '')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
    const structuredIntro = BookFieldSanitizer.extractStructuredIntro(cleaned);
    if (structuredIntro) return structuredIntro;
    // Some explore rules accidentally return the whole JSON record as the intro. Do not flash that record on
    // the detail page while the real book-info request is still running.
    if (/^[\[{]/.test(cleaned) && /"(?:type|name|author|cover|status|data)"\s*:/i.test(cleaned)) return '';
    return cleaned;
  }

  private static extractStructuredIntro(value: string): string {
    if (!/^[\[{]/.test(value || '')) return '';
    const keys = ['desc', 'intro', 'description', 'abstract'];
    for (const key of keys) {
      const match = new RegExp(`"${key}"\\s*:\\s*"((?:\\\\.|[^"\\\\])*)"`, 'i').exec(value);
      if (!match || !match[1]) continue;
      try {
        const decoded = String(JSON.parse(`"${match[1]}"`));
        if (decoded.trim()) return BookFieldSanitizer.clean(decoded);
      } catch (_) {
        const fallback = match[1].replace(/\\n/g, '\n').replace(/\\"/g, '"').trim();
        if (fallback) return fallback;
      }
    }
    return '';
  }

  static isUnresolved(value: string): boolean {
    const text = (value || '').trim();
    if (!text) return true;
    if (/^(?:undefined|null)$/i.test(text)) return true;
    return text.includes('{{') || text.includes('}}') || text.includes('@js:') || text.includes('java.') ||
      text.includes('result.replace') || /(^|[^\w])\$\.\.?[A-Za-z_]/.test(text);
  }
}
