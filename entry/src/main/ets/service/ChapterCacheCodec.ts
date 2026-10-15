type CachedChapter = { variables?: Record<string, string> };

/** Read old array sidecars one chapter at a time, without materializing the
 * repeated source definitions written by older versions in the shared heap. */
export class ChapterCacheCodec {
  static parse<T extends CachedChapter>(json: string): T[] {
    const chapters: T[] = [];
    let cursor = 0;
    const skipSpace = (): void => { while (cursor < json.length && /\s/.test(json[cursor])) cursor++; };
    skipSpace();
    if (json[cursor++] !== '[') throw new Error('Invalid chapter cache');
    skipSpace();
    if (json[cursor] === ']') {
      cursor++; skipSpace();
      if (cursor !== json.length) throw new Error('Invalid chapter cache');
      return chapters;
    }
    const strings = new Map<string, string>();
    while (cursor < json.length) {
      skipSpace();
      if (json[cursor] !== '{') throw new Error('Invalid chapter cache');
      const start = cursor;
      let depth = 0, quoted = false, escaped = false;
      do {
        const ch = json[cursor++];
        if (quoted) {
          if (escaped) escaped = false;
          else if (ch === '\\') escaped = true;
          else if (ch === '"') quoted = false;
        } else if (ch === '"') quoted = true;
        else if (ch === '{' || ch === '[') depth++;
        else if (ch === '}' || ch === ']') depth--;
      } while (cursor < json.length && (depth > 0 || quoted));
      if (depth !== 0 || quoted) throw new Error('Invalid chapter cache');
      const chapter: T = JSON.parse(json.slice(start, cursor));
      if (chapter.variables) {
        delete chapter.variables.__audioTocDefinition;
        for (const key of Object.keys(chapter.variables)) {
          const value = chapter.variables[key];
          if (typeof value !== 'string') continue;
          const shared = strings.get(value);
          if (shared !== undefined) chapter.variables[key] = shared;
          else if (strings.size < 4096) strings.set(value, value);
        }
      }
      chapters.push(chapter);
      skipSpace();
      const separator = json[cursor++];
      if (separator === ']') {
        skipSpace();
        if (cursor !== json.length) throw new Error('Invalid chapter cache');
        return chapters;
      }
      if (separator !== ',') throw new Error('Invalid chapter cache');
    }
    throw new Error('Incomplete chapter cache');
  }

  static stringify<T>(chapter: T): string {
    // Do not mutate live chapter state while a queued write is in progress.
    return JSON.stringify(chapter, (key, value) => key === '__audioTocDefinition' ? undefined : value);
  }
}
