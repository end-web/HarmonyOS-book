import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { picker } from '@kit.CoreFileKit';
import { zlib, emitter } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { media } from '@kit.MediaKit';
import { AppColor, AppRadius, AppSpace, AppFont } from '../theme/Theme';
import { Book, Chapter, AudioSource } from '../model/Book';
import { DataService } from '../service/DataService';
import { PreferenceService } from '../service/PreferenceService';
import { WindowUtils } from '../utils/WindowUtils';

export const EVT_SWITCH_TAB = 'app.nav.switchTab';
const TAB_INDEX_FAVORITE = 1;

interface PickedFile {
  uri: string;
  name: string;
  ext: string;
}

const AUDIO_EXTS: string[] = ['.mp3', '.m4a', '.flac', '.wav', '.ogg', '.aac'];

@ComponentV2
export struct ImportPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local bookTitle: string = '';
  @Local bookAuthor: string = '';
  @Local pickedFiles: PickedFile[] = [];
  @Local coverPath: string = '';
  @Local importing: boolean = false;
  @Local importDone: boolean = false;
  @Local progressText: string = '';

  private context: common.UIAbilityContext | null = null;

  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async pickFiles(): Promise<void> {
    try {
      const opt = new picker.DocumentSelectOptions();
      opt.maxSelectNumber = 50;
      opt.fileSuffixFilters = ['.mp3', '.m4a', '.flac', '.wav', '.ogg', '.aac', '.zip'];
      const dp = new picker.DocumentViewPicker(this.context!);
      const uris = await dp.select(opt);
      if (!uris || uris.length === 0) return;
      const files: PickedFile[] = [];
      for (const uri of uris) {
        const name = this.extractFileName(uri);
        const ext = this.extractExt(uri);
        files.push({ uri, name, ext });
      }
      this.pickedFiles = files;
      if (files.length === 1 && !this.bookTitle) {
        this.bookTitle = files[0].name;
      }
    } catch (e) {
      // user cancelled or error
    }
  }

  private async pickCover(): Promise<void> {
    try {
      const opt = new photoAccessHelper.PhotoSelectOptions();
      opt.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      opt.maxSelectNumber = 1;
      const pp = new photoAccessHelper.PhotoViewPicker();
      const result = await pp.select(opt);
      if (!result || !result.photoUris || result.photoUris.length === 0) return;
      const srcUri = result.photoUris[0];
      const ext = this.extractExt(srcUri) || '.jpg';
      const dir = this.context!.filesDir + '/covers';
      try { await fileIo.mkdir(dir, true); } catch (_e) { /* exists */ }
      const dest = `${dir}/cover_${Date.now()}${ext}`;
      const src = await fileIo.open(srcUri, fileIo.OpenMode.READ_ONLY);
      const dst = await fileIo.open(dest, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      await fileIo.copyFile(src.fd, dst.fd);
      await fileIo.close(src);
      await fileIo.close(dst);
      this.coverPath = dest;
    } catch (e) {
      // cancelled
    }
  }

  private extractFileName(uri: string): string {
    try {
      const fullName = new fileUri.FileUri(uri).name;
      const dotIdx = fullName.lastIndexOf('.');
      return dotIdx > 0 ? fullName.substring(0, dotIdx) : fullName;
    } catch (_e) {
      return '';
    }
  }

  private extractExt(uri: string): string {
    try {
      const fullName = new fileUri.FileUri(uri).name;
      const dotIdx = fullName.lastIndexOf('.');
      return dotIdx > 0 ? fullName.substring(dotIdx).toLowerCase() : '';
    } catch (_e) {
      return '';
    }
  }

  private isAudioExt(ext: string): boolean {
    return AUDIO_EXTS.includes(ext);
  }

  /**
   * 自然排序：把"第1集"、"第10集"、"track 02" 这类文件名按数字段大小比较。
   * 拆为 [文本, 数字, 文本, ...] 数组，逐段对比，数字段当数字比，文本段忽略大小写按 locale 比。
   */
  private naturalCompare(a: string, b: string): number {
    const tokenize = (s: string): string[] => {
      const arr: string[] = [];
      const re = /(\d+)|(\D+)/g;
      let m: RegExpExecArray | null = re.exec(s);
      while (m !== null) {
        arr.push(m[0]);
        m = re.exec(s);
      }
      return arr;
    };
    const sa = tokenize(a.toLowerCase());
    const sb = tokenize(b.toLowerCase());
    const len = Math.min(sa.length, sb.length);
    for (let i = 0; i < len; i++) {
      const xa = sa[i];
      const xb = sb[i];
      const na = parseInt(xa, 10);
      const nb = parseInt(xb, 10);
      const aIsNum = !isNaN(na) && /^\d+$/.test(xa);
      const bIsNum = !isNaN(nb) && /^\d+$/.test(xb);
      if (aIsNum && bIsNum) {
        if (na !== nb) return na - nb;
      } else {
        if (xa < xb) return -1;
        if (xa > xb) return 1;
      }
    }
    return sa.length - sb.length;
  }

  /**
   * 解压一个 zip 到沙箱临时目录，递归收集其中所有支持的音频/小说文件，转为 PickedFile。
   * zip 文件本身需要先复制到沙箱（zlib.decompressFile 不接受 file:// content uri）。
   */
  private async expandZip(pf: PickedFile, extractRoot: string): Promise<PickedFile[]> {
    const stamp = Date.now().toString() + '_' + Math.floor(Math.random() * 1000);
    const cachedZip = `${extractRoot}/_src_${stamp}.zip`;
    const outDir = `${extractRoot}/${pf.name}_${stamp}`;

    // 把 content uri 的 zip 复制到沙箱；try/finally 确保异常时也关闭 fd，避免泄漏
    let sf: fileIo.File | null = null;
    let df: fileIo.File | null = null;
    try {
      await fileIo.mkdir(outDir, true);
      sf = await fileIo.open(pf.uri, fileIo.OpenMode.READ_ONLY);
      df = await fileIo.open(cachedZip, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      await fileIo.copyFile(sf.fd, df.fd);
    } catch (e) {
      throw new Error('准备解压失败: ' + (e as Error).message);
    } finally {
      if (sf) { try { await fileIo.close(sf); } catch (_e) { /* ignore */ } }
      if (df) { try { await fileIo.close(df); } catch (_e) { /* ignore */ } }
    }

    this.progressText = `解压 ${pf.name}.zip`;
    await new Promise<void>((resolve, reject) => {
      zlib.decompressFile(cachedZip, outDir, {}, (err) => {
        if (err) reject(new Error(err.message || '解压失败'));
        else resolve();
      });
    });
    try { await fileIo.unlink(cachedZip); } catch (_e) { /* ignore */ }

    const collected: PickedFile[] = [];
    this.walkDir(outDir, collected);
    return collected;
  }

  /**
   * 递归遍历目录，把音频/小说文件收集为 PickedFile（uri 用沙箱绝对路径，AVPlayer/fileIo 都能识别）。
   */
  private walkDir(dir: string, out: PickedFile[]): void {
    let entries: string[] = [];
    try {
      entries = fileIo.listFileSync(dir);
    } catch (_e) {
      return;
    }
    for (const name of entries) {
      const full = `${dir}/${name}`;
      let isDir = false;
      try {
        isDir = fileIo.statSync(full).isDirectory();
      } catch (_e) {
        continue;
      }
      if (isDir) {
        this.walkDir(full, out);
        continue;
      }
      const dot = name.lastIndexOf('.');
      if (dot <= 0) continue;
      const ext = name.substring(dot).toLowerCase();
      const base = name.substring(0, dot);
      if (this.isAudioExt(ext)) {
        out.push({ uri: full, name: base, ext });
      }
    }
  }

  private async doImport(): Promise<void> {
    if (this.pickedFiles.length === 0 || !this.bookTitle) return;
    this.importing = true;
    this.progressText = '准备中...';
    const bookId = 'import_' + Date.now().toString();
    const extractRoot = `${this.context!.cacheDir}/import_extract_${bookId}`;
    let needCleanup = false;

    try {
      // 1. 展开所有 zip
      const expanded: PickedFile[] = [];
      for (const pf of this.pickedFiles) {
        if (pf.ext === '.zip') {
          if (!needCleanup) {
            await fileIo.mkdir(extractRoot, true);
            needCleanup = true;
          }
          try {
            const inner = await this.expandZip(pf, extractRoot);
            if (inner.length === 0) {
              this.progressText = `${pf.name}.zip 内未发现可导入文件`;
            }
            expanded.push(...inner);
          } catch (e) {
            this.progressText = `解压失败: ${pf.name}.zip`;
            console.error('Unzip failed:', pf.name, e);
          }
        } else {
          expanded.push(pf);
        }
      }

      if (expanded.length === 0) {
        this.importing = false;
        this.progressText = '没有可导入的文件';
        return;
      }

      // 2. 按集数自然排序
      expanded.sort((a, b) => this.naturalCompare(a.name, b.name));

      const audioFiles = expanded.filter(f => this.isAudioExt(f.ext));
      if (audioFiles.length === 0) {
        this.importing = false;
        this.progressText = '没有可导入的音频文件';
        return;
      }

      const dir = this.context!.filesDir + '/audio/' + bookId;
      await fileIo.mkdir(dir, true);
      const book = await this.importAudioBook(bookId, dir, audioFiles);
      await DataService.addImportedBook(book);
      await PreferenceService.toggleFavorite(book.id);

      this.importing = false;
      this.progressText = '';
      this.importDone = true;
      try {
        this.getUIContext().getPromptAction().showToast({ message: '导入成功，已加入书架', duration: 1800 });
      } catch (_e) { /* ignore */ }
      emitter.emit(EVT_SWITCH_TAB, { data: { index: TAB_INDEX_FAVORITE } });
      this.navStack.pop();
    } catch (err) {
      this.importing = false;
      this.progressText = '导入失败: ' + (err as Error).message;
      console.error('Import failed:', err);
    } finally {
      if (needCleanup) {
        try { await fileIo.rmdir(extractRoot); } catch (_e) { /* ignore */ }
      }
    }
  }

  private async probeAudioDuration(path: string): Promise<number> {
    let f: fileIo.File | null = null;
    let extractor: media.AVMetadataExtractor | null = null;
    try {
      f = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(f.fd);
      if (stat.size <= 0) return 0;
      extractor = await media.createAVMetadataExtractor();
      extractor.fdSrc = { fd: f.fd, offset: 0, length: stat.size };
      const meta = await extractor.fetchMetadata();
      // AVMetadata.duration 单位为毫秒(ms)，章节存秒
      const ms = meta && meta.duration ? Number(meta.duration) : 0;
      return ms > 0 ? Math.round(ms / 1_000) : 0;
    } catch (_e) {
      return 0;
    } finally {
      if (extractor) {
        try { await extractor.release(); } catch (_e) { /* ignore */ }
      }
      if (f) {
        try { await fileIo.close(f); } catch (_e) { /* ignore */ }
      }
    }
  }

  private async importAudioBook(bookId: string, sandboxDir: string, files: PickedFile[]): Promise<Book> {
    const chapters: Chapter[] = [];
    for (let i = 0; i < files.length; i++) {
      const pf = files[i];
      this.progressText = `导入音频 ${i + 1}/${files.length}`;
      const destName = (i + 1) + pf.ext;
      const destPath = sandboxDir + '/' + destName;
      try {
        const srcFile = await fileIo.open(pf.uri, fileIo.OpenMode.READ_ONLY);
        const dstFile = await fileIo.open(destPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
        await fileIo.copyFile(srcFile.fd, dstFile.fd);
        await fileIo.close(srcFile);
        await fileIo.close(dstFile);
      } catch (e) {
        continue;
      }
      const durationSec = await this.probeAudioDuration(destPath);
      const src: AudioSource = { type: 'file', value: destPath };
      chapters.push({ id: bookId + '-c' + (i + 1), index: i + 1, title: pf.name, duration: durationSec, source: src });
    }
    return {
      id: bookId, title: this.bookTitle, author: this.bookAuthor || '未知',
      narrator: '', cover: this.coverPath, category: 'import', intro: '本地导入',
      totalDuration: 0, chapterCount: chapters.length, rating: 0,
      tags: ['本地导入'], chapters: chapters, bookUrl: '', sourceUrl: ''
    };
  }

  // PLACEHOLDER_BUILD
  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24)
            .fontColor([$r('sys.color.font_primary')])
            .onClick(() => this.navStack.pop())
          Text('本地导入')
            .fontSize(AppFont.Title)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Bold)
            .margin({ left: AppSpace.Sm })
        }
        .width('100%')
        .padding({
          top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
          left: AppSpace.Md, right: AppSpace.Md, bottom: AppSpace.Md
        })

        Scroll() {
          Column({ space: AppSpace.Lg }) {
            this.buildFileSection()
            this.buildCoverSection()
            this.buildInfoSection()
          }
          .width('100%')
          .padding({
            left: AppSpace.Md, right: AppSpace.Md,
            top: AppSpace.Sm,
            bottom: 96 + WindowUtils.getBottomSafeVp()
          })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')

      this.buildActionBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  buildFileSection() {
    Column({ space: AppSpace.Sm }) {
      Text('选择文件')
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))

      Column() {
        if (this.pickedFiles.length === 0) {
          Column({ space: AppSpace.Sm }) {
            SymbolGlyph($r('sys.symbol.plus_circle'))
              .fontSize(40)
              .fontColor([AppColor.Brand])
            Text('点击选择文件')
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_secondary'))
            Text('音频:mp3/m4a/flac/wav/ogg/aac  打包:zip')
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
            Text('支持选 .zip 自动解压；多文件按集数自然排序')
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .height(140)
        } else {
          Column({ space: 0 }) {
            ForEach(this.pickedFiles, (pf: PickedFile, idx: number) => {
              Row({ space: AppSpace.Sm }) {
                Text((idx + 1).toString())
                  .fontSize(AppFont.Caption)
                  .fontColor($r('sys.color.font_tertiary'))
                  .width(24)
                Text(pf.name + pf.ext)
                  .fontSize(AppFont.Body)
                  .fontColor($r('sys.color.font_secondary'))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Xs, bottom: AppSpace.Xs })
            }, (pf: PickedFile) => pf.uri)

            Row({ space: AppSpace.Sm }) {
              Text('重新选择')
                .fontSize(AppFont.Body)
                .fontColor(AppColor.Brand)
                .onClick(() => this.pickFiles())
              Text(this.pickedFiles.length + ' 个文件')
                .fontSize(AppFont.Caption)
                .fontColor($r('sys.color.font_tertiary'))
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Sm, bottom: AppSpace.Sm })
          }
          .width('100%')
        }
      }
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius(AppRadius.Lg)
      .onClick(() => { if (this.pickedFiles.length === 0) this.pickFiles(); })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // PLACEHOLDER_BUILDERS
  @Builder
  buildCoverSection() {
    Column({ space: AppSpace.Sm }) {
      Text('封面（可选）')
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))

      Row({ space: AppSpace.Md }) {
        Stack() {
          if (this.coverPath) {
            Image('file://' + this.coverPath)
              .width(80)
              .height(112)
              .borderRadius(AppRadius.Md)
              .objectFit(ImageFit.Cover)
          } else {
            Stack() {
              Column()
                .width('100%')
                .height('100%')
                .backgroundColor(AppColor.Brand)
                .borderRadius(AppRadius.Md)
              Text(this.bookTitle ? this.bookTitle.substring(0, 1) : '?')
                .fontSize(36)
                .fontColor(Color.White)
                .fontWeight(FontWeight.Bold)
            }
            .width(80)
            .height(112)
            .borderRadius(AppRadius.Md)
            .clip(true)
          }
        }
        .onClick(() => this.pickCover())

        Column({ space: AppSpace.Xs }) {
          Text(this.coverPath ? '点击图片可更换' : '未选封面，将用书名首字占位')
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(2)
          Row({ space: AppSpace.Sm }) {
            Text(this.coverPath ? '更换' : '上传封面')
              .fontSize(AppFont.Body)
              .fontColor(AppColor.Brand)
              .onClick(() => this.pickCover())
            if (this.coverPath) {
              Text('移除')
                .fontSize(AppFont.Body)
                .fontColor($r('sys.color.font_tertiary'))
                .onClick(() => { this.coverPath = ''; })
            }
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding(AppSpace.Md)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius(AppRadius.Lg)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildInfoSection() {
    Column({ space: AppSpace.Sm }) {
      Text('书籍信息')
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))

      Column({ space: AppSpace.Sm }) {
        TextInput({ placeholder: '书名（必填）', text: this.bookTitle!! })
          .height(44)
          .backgroundColor($r('sys.color.comp_background_primary'))
          .borderRadius(AppRadius.Md)
          .padding({ left: AppSpace.Md, right: AppSpace.Md })

        TextInput({ placeholder: '作者（选填）', text: this.bookAuthor!! })
          .height(44)
          .backgroundColor($r('sys.color.comp_background_primary'))
          .borderRadius(AppRadius.Md)
          .padding({ left: AppSpace.Md, right: AppSpace.Md })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildActionBar() {
    Column() {
      if (this.importing && this.progressText) {
        Text(this.progressText)
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .margin({ bottom: AppSpace.Sm })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      Button(this.importing ? '导入中...' : '开始导入')
        .width('100%')
        .height(48)
        .backgroundColor(this.canImport() ? AppColor.Brand : AppColor.BrandDisabled)
        .fontColor(Color.White)
        .fontSize(AppFont.BodyL)
        .borderRadius(AppRadius.Md)
        .enabled(this.canImport() && !this.importing)
        .onClick(() => this.doImport())
    }
    .width('100%')
    .padding({
      left: AppSpace.Md, right: AppSpace.Md,
      top: AppSpace.Sm,
      bottom: AppSpace.Sm + WindowUtils.getBottomSafeVp()
    })
    .backgroundColor($r('sys.color.background_primary'))
    .border({ width: { top: 0.5 }, color: $r('sys.color.comp_divider') })
  }

  private canImport(): boolean {
    return this.pickedFiles.length > 0 && this.bookTitle.length > 0;
  }
}