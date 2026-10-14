/**
 * Legado page-candidate shorthand in request addresses: `<first,second,...>`.
 *
 * Page N takes the N-th candidate and every page past the list keeps the last one, so
 * `/list/<,index_{{page}}.html>` requests `/list/` first and `/list/index_2.html` next. Android
 * Legado resolves the shorthand after the address scripts and `{{...}}` templates have run; a
 * candidate may therefore still contain a page template when it is applied earlier.
 */
export class PageCandidateUrl {
  /**
   * @param requirePageTemplate only rewrite groups that mention `{{page}}`/`{{pageIndex}}`. Use it
   * for text that is still JavaScript source, where `a < b, c > d` is an ordinary expression.
   */
  static apply(url: string, page: number, requirePageTemplate: boolean = false): string {
    const value = url || '';
    if (!value.includes('<') || !value.includes(',')) return value;
    const pageNumber = Number.isFinite(page) && page >= 1 ? Math.floor(page) : 1;
    return value.replace(/<([^<>]*)>/g, (match: string, inner: string): string => {
      // Markup attributes, call arguments and multi-line text are never page candidates. A
      // `{{...}}` expression inside a candidate may use any of those characters.
      if (/[()"'\r\n]/.test(inner.replace(/\{\{[\s\S]*?\}\}/g, ''))) return match;
      if (requirePageTemplate && !/\{\{\s*page(?:Index)?\b/i.test(inner)) return match;
      const candidates = this.splitCandidates(inner);
      if (candidates.length < 2) return match;
      return candidates[Math.min(pageNumber, candidates.length) - 1].trim();
    });
  }

  /** A comma inside `{{...}}` belongs to the template expression, not to the candidate list. */
  private static splitCandidates(inner: string): string[] {
    const candidates: string[] = [];
    let depth = 0;
    let start = 0;
    for (let index = 0; index < inner.length; index++) {
      if (inner.startsWith('{{', index)) {
        depth++;
        index++;
      } else if (inner.startsWith('}}', index) && depth > 0) {
        depth--;
        index++;
      } else if (inner.charAt(index) === ',' && depth === 0) {
        candidates.push(inner.substring(start, index));
        start = index + 1;
      }
    }
    candidates.push(inner.substring(start));
    return candidates;
  }
}
