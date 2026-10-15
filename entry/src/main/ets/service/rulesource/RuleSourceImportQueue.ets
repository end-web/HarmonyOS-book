/** 外部文件请求独立于页面参数，页面复用和首次加载都不会覆盖尚未导入的 URI。 */
@ObservedV2
export class RuleSourceImportQueue {
  private static instance: RuleSourceImportQueue = new RuleSourceImportQueue();
  @Trace revision: number = 0;
  private uris: string[] = [];
  private consuming: boolean = false;

  static getInstance(): RuleSourceImportQueue {
    return RuleSourceImportQueue.instance;
  }

  open(navStack: NavPathStack, uri: string): void {
    if (uri.length === 0) return;
    const indexes = navStack.getIndexByName('ruleSources');
    // 保留最近的管理页；兼容已经积累的重复页面，不清空其他页面。
    if (indexes.length > 1) navStack.removeByIndexes(indexes.slice(0, -1));
    this.uris.push(uri);
    this.revision++;
    if (indexes.length > 0) {
      navStack.moveToTop('ruleSources', false);
    } else {
      navStack.pushPathByName('ruleSources', null, false);
    }
  }

  take(): string | undefined {
    return this.uris.shift();
  }

  hasPending(): boolean {
    return this.uris.length > 0;
  }

  tryBegin(): boolean {
    if (this.consuming) return false;
    this.consuming = true;
    return true;
  }

  finish(): void {
    this.consuming = false;
    if (this.hasPending()) this.revision++;
  }
}
