import { emitter } from '@kit.BasicServicesKit';
import { DownloadService, EVT_DOWNLOAD_UPDATED } from '../service/DownloadService';
import { DownloadBookRecord } from '../service/DownloadStore';
import { DownloadPolicy } from '../service/DownloadPolicy';
import { AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct DownloadManagerPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local refreshTick: number = 0;

  private downloadHandler = (): void => {
    this.refreshTick = this.refreshTick + 1;
  };

  aboutToAppear(): void {
    emitter.on(EVT_DOWNLOAD_UPDATED, this.downloadHandler);
  }

  aboutToDisappear(): void {
    emitter.off(EVT_DOWNLOAD_UPDATED, this.downloadHandler);
  }

  private records(): DownloadBookRecord[] {
    if (this.refreshTick < 0) return [];
    return DownloadService.getInstance().getAllBookStatuses()
      .filter((item: DownloadBookRecord) => item.chapters.some((chapter) => chapter.status !== 'deleted'))
      .sort((a: DownloadBookRecord, b: DownloadBookRecord) => b.updatedAt - a.updatedAt);
  }

  private totalBytes(): number {
    return this.records().reduce((sum: number, item: DownloadBookRecord) => sum + item.totalBytes, 0);
  }

  private formatBytes(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
  }

  private statusText(record: DownloadBookRecord): string {
    const total = Math.max(record.chapterCount, record.chapters.length);
    if (record.status === 'paused') return `已暂停 · ${record.downloadedCount}/${total}`;
    if (record.status === 'downloading' || record.status === 'queued') {
      return `下载中 · ${record.downloadedCount}/${total}`;
    }
    if (record.failedCount > 0) {
      const failed = record.chapters.find((item) => item.status === 'failed');
      const reason = failed ? DownloadPolicy.failureText(failed.failureCode
        ?? DownloadPolicy.classifyFailure(failed.failureReason)) : '下载失败，请重试';
      return `${record.downloadedCount}/${total} · 失败 ${record.failedCount} · ${reason}`;
    }
    return `已完成 · ${record.downloadedCount}/${total}`;
  }

  private showToast(message: string): void {
    try { this.getUIContext().getPromptAction().showToast({ message }); } catch (_e) { /* ignore */ }
  }

  private async pause(record: DownloadBookRecord): Promise<void> {
    try {
      await DownloadService.getInstance().pauseBook(record.bookId);
    } catch (_e) {
      this.showToast('暂停下载失败，请重试');
    }
  }

  private async resume(record: DownloadBookRecord): Promise<void> {
    try {
      await DownloadService.getInstance().resumeBook(record.bookId);
    } catch (_e) {
      this.showToast('继续下载失败，请重试');
    }
  }

  private confirmDelete(record: DownloadBookRecord): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '删除下载',
      message: `删除《${record.title}》的全部离线音频？不会移出书架。`,
      buttons: [
        { text: '取消', color: '#8F8F8F' },
        { text: '删除', color: '#D03050' }
      ]
    }).then((result) => {
      if (result.index !== 1) return;
      DownloadService.getInstance().deleteBookDownload(record.bookId)
        .catch(() => this.showToast('删除下载失败，请重试'));
    }).catch(() => { /* ignore */ });
  }

  private openBook(record: DownloadBookRecord): void {
    this.navStack.pushPathByName('detail', record.bookId);
  }

  build() {
    Column() {
      this.buildHeader()
      if (this.records().length === 0) {
        this.buildEmpty()
      } else {
        List({ space: AppSpace.Sm }) {
          ForEach(this.records(), (record: DownloadBookRecord) => {
            ListItem() {
              this.buildRecord(record)
            }
          }, (record: DownloadBookRecord) => record.bookId)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: AppSpace.Md, right: AppSpace.Md, bottom: AppSpace.Xl })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_secondary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  buildHeader() {
    Row() {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(24)
        .fontColor([$r('sys.color.font_primary')])
        .onClick(() => this.navStack.pop())
      Column({ space: 2 }) {
        Text('下载管理')
          .fontSize(AppFont.TitleL)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
        Text(`${this.records().length} 本 · ${this.formatBytes(this.totalBytes())}`)
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: AppSpace.Sm })
    }
    .width('100%')
    .padding({
      top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
      left: AppSpace.Md,
      right: AppSpace.Md,
      bottom: AppSpace.Md
    })
  }

  @Builder
  buildEmpty() {
    Column({ space: AppSpace.Sm }) {
      SymbolGlyph($r('sys.symbol.arrow_down_circle'))
        .fontSize(42)
        .fontColor([$r('sys.color.font_tertiary')])
      Text('暂无离线下载')
        .fontSize(AppFont.BodyL)
        .fontColor($r('sys.color.font_secondary'))
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildRecord(record: DownloadBookRecord) {
    Column({ space: AppSpace.Sm }) {
      Row({ space: AppSpace.Md }) {
        this.buildCover(record)
        Column({ space: 4 }) {
          Text(record.title)
            .fontSize(AppFont.BodyL)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(record.author || '未知作者')
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
          Text(this.statusText(record))
            .fontSize(AppFont.Caption)
            .fontColor(record.failedCount > 0 ? '#D03050' : $r('sys.color.font_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Text(this.formatBytes(record.totalBytes))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick(() => this.openBook(record))

      Row({ space: AppSpace.Sm }) {
        if (record.status === 'downloading' || record.status === 'queued') {
          this.buildAction($r('sys.symbol.pause_fill'), '暂停', () => this.pause(record), false)
        } else if (record.status === 'paused' || record.failedCount > 0) {
          this.buildAction($r('sys.symbol.play_fill'), record.failedCount > 0 ? '重试' : '继续',
            () => this.resume(record), false)
        }
        this.buildAction($r('sys.symbol.trash'), '删除', () => this.confirmDelete(record), true)
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .padding(AppSpace.Md)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Lg)
  }

  @Builder
  buildCover(record: DownloadBookRecord) {
    if (record.cover && record.cover.startsWith('http')) {
      Image(record.cover)
        .width(52)
        .height(68)
        .objectFit(ImageFit.Cover)
        .borderRadius(AppRadius.Sm)
    } else if (record.cover && (record.cover.startsWith('/') || record.cover.startsWith('file://'))) {
      Image('file://' + record.cover.replace(/^file:\/\//, ''))
        .width(52)
        .height(68)
        .objectFit(ImageFit.Cover)
        .borderRadius(AppRadius.Sm)
    } else {
      Stack() {
        SymbolGlyph($r('sys.symbol.arrow_down_circle'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_tertiary')])
      }
      .width(52)
      .height(68)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .borderRadius(AppRadius.Sm)
    }
  }

  @Builder
  buildAction(icon: Resource, text: string, action: () => void, danger: boolean) {
    Row({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(15)
        .fontColor([danger ? '#D03050' : $r('sys.color.font_secondary')])
      Text(text)
        .fontSize(AppFont.Caption)
        .fontColor(danger ? '#D03050' : $r('sys.color.font_secondary'))
    }
    .height(32)
    .padding({ left: AppSpace.Sm, right: AppSpace.Sm })
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .borderRadius(AppRadius.Md)
    .onClick(() => action())
  }
}
