/** Keep chapter metadata across the JSON boundary, including old saved catalogs. */
export class ChapterRuleContext {
  static create(title: string, index: number, variables: Record<string, string> = {}): Record<string, string> {
    const context: Record<string, string> = { ...variables };
    // Fresh catalogs retain the rule title before UI book-name prefix removal.
    context.chapterName = variables.chapterName || title;
    context.chapterIndex = String(Math.max(0, index));
    return context;
  }
}
