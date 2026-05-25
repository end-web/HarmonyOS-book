import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { AppColor, AppRadius, AppSpace, AppFont } from '../theme/Theme';
import { Book, Chapter, AudioSource } from '../model/Book';
import { DataService } from '../service/DataService';
import { PreferenceService } from '../service/PreferenceService';
import { TextSplitter, ChapterText } from '../utils/TextSplitter';
import { WindowUtils } from '../utils/WindowUtils';

interface PickedFile {
  uri: string;
  name: string;
  ext: string;
}

const AUDIO_EXTS: string[] = ['.mp3', '.m4a', '.flac', '.wav', '.ogg', '.aac'];
const NOVEL_EXTS: string[] = ['.txt', '.epub'];

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

  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  private async pickFiles(): Promise<void> {
    try {
      const opt = new picker.DocumentSelectOptions();
      opt.maxSelectNumber = 50;
      opt.fileSuffixFilters = ['.mp3', '.m4a', '.flac', '.wav', '.ogg', '.aac', '.txt', '.epub'];
      const dp = new picker.DocumentViewPicker(this.context);
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
      const dir = this.context.filesDir + '/covers';
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
    const parts = uri.split('/');
    const last = parts[parts.length - 1];
    const dotIdx = last.lastIndexOf('.');
    return dotIdx > 0 ? last.substring(0, dotIdx) : last;
  }

  private extractExt(uri: string): string {
    const dotIdx = uri.lastIndexOf('.');
    return dotIdx > 0 ? uri.substring(dotIdx).toLowerCase() : '';
  }

  private isNovelFile(ext: string): boolean {
    return NOVEL_EXTS.includes(ext);
  }

  private async doImport(): Promise<void> {
    if (this.pickedFiles.length === 0 || !this.bookTitle) return;
    this.importing = true;
    this.progressText = '准备中...';
    const bookId = 'import_' + Date.now().toString();

    const novelFiles = this.pickedFiles.filter(f => this.isNovelFile(f.ext));
    const audioFiles = this.pickedFiles.filter(f => !this.isNovelFile(f.ext));

    if (novelFiles.length > 0) {
      const dir = this.context.filesDir + '/novel/' + bookId;
      await fileIo.mkdir(dir, true);
      const book = await this.importNovelBook(bookId, dir, novelFiles);
      await DataService.addImportedBook(book);
      await PreferenceService.toggleFavorite(book.id);
    }
    if (audioFiles.length > 0) {
      const aid = novelFiles.length > 0 ? bookId + '_audio' : bookId;
      const dir = this.context.filesDir + '/audio/' + aid;
      await fileIo.mkdir(dir, true);
      const book = await this.importAudioBook(aid, dir, audioFiles);
      await DataService.addImportedBook(book);
      await PreferenceService.toggleFavorite(book.id);
    }

    this.importing = false;
    this.progressText = '';
    this.importDone = true;
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
      const src: AudioSource = { type: 'file', value: destPath };
      chapters.push({ id: bookId + '-c' + (i + 1), index: i + 1, title: pf.name, duration: 0, source: src });
    }
    return {
      id: bookId, title: this.bookTitle, author: this.bookAuthor || '未知',
      narrator: '', cover: this.coverPath, category: 'import', intro: '本地导入',
      totalDuration: 0, chapterCount: chapters.length, rating: 0,
      tags: ['本地导入'], chapters: chapters, bookUrl: '', sourceUrl: ''
    };
  }

  private async importNovelBook(bookId: string, sandboxDir: string, files: PickedFile[]): Promise<Book> {
    const allChapters: Chapter[] = [];
    let chapterIdx = 0;

    for (let f = 0; f < files.length; f++) {
      const pf = files[f];
      this.progressText = `读取 ${pf.name + pf.ext}`;

      if (pf.ext === '.epub') {
        // epub 暂不解析，原样保存为单章节
        const destPath = sandboxDir + '/' + pf.name + pf.ext;
        try {
          const srcFile = await fileIo.open(pf.uri, fileIo.OpenMode.READ_ONLY);
          const dstFile = await fileIo.open(destPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
          await fileIo.copyFile(srcFile.fd, dstFile.fd);
          await fileIo.close(srcFile);
          await fileIo.close(dstFile);
        } catch (_e) { continue; }
        chapterIdx++;
        allChapters.push({
          id: bookId + '-c' + chapterIdx, index: chapterIdx,
          title: pf.name, duration: 0,
          source: { type: 'file', value: destPath }
        });
        continue;
      }

      // txt: 读取 + 解码 + 切章
      const text = await this.readPickedText(pf.uri);
      this.progressText = `切分章节 ${pf.name}`;
      const chunks: ChapterText[] = TextSplitter.split(text, pf.name);

      for (let i = 0; i < chunks.length; i++) {
        const ch = chunks[i];
        chapterIdx++;
        const destPath = `${sandboxDir}/c_${chapterIdx}.txt`;
        try {
          const dst = await fileIo.open(destPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
          const encoder = util.TextEncoder.create('utf-8');
          const buf = encoder.encodeInto(ch.content);
          await fileIo.write(dst.fd, buf.buffer);
          await fileIo.close(dst);
        } catch (_e) { continue; }
        allChapters.push({
          id: bookId + '-c' + chapterIdx, index: chapterIdx,
          title: ch.title, duration: 0,
          source: { type: 'file', value: destPath }
        });
        if (i % 50 === 0) {
          this.progressText = `写入章节 ${i + 1}/${chunks.length}`;
        }
      }
    }

    return {
      id: bookId, title: this.bookTitle, author: this.bookAuthor || '未知',
      narrator: '', cover: this.coverPath, category: 'novel', intro: '本地小说',
      totalDuration: 0, chapterCount: allChapters.length, rating: 0,
      tags: ['本地小说'], chapters: allChapters, bookUrl: '', sourceUrl: ''
    };
  }

  private async readPickedText(uri: string): Promise<string> {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = await fileIo.stat(file.fd);
      const size = stat.size;
      if (size === 0) return '';
      const buf = new ArrayBuffer(size);
      await fileIo.read(file.fd, buf);
      const bytes = new Uint8Array(buf);
      try {
        const dec = util.TextDecoder.create('utf-8', { fatal: true, ignoreBOM: false });
        return dec.decodeToString(bytes);
      } catch (_e) {
        try {
          const dec = util.TextDecoder.create('gbk');
          return dec.decodeToString(bytes);
        } catch (_e2) {
          const dec = util.TextDecoder.create('utf-8');
          return dec.decodeToString(bytes);
        }
      }
    } finally {
      await fileIo.close(file);
    }
  }

  // PLACEHOLDER_BUILD
  build() {
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
          this.buildActionButton()
        }
        .width('100%')
        .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Sm })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
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
            Text('音频:mp3/m4a/flac/wav/ogg/aac  小说:txt/epub')
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
            }, (pf: PickedFile, idx: number) => idx.toString())

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
  buildActionButton() {
    if (this.importDone) {
      Column({ space: AppSpace.Sm }) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(48)
          .fontColor([AppColor.Brand])
        Text('导入成功')
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_secondary'))
        Button('返回')
          .width(120)
          .height(40)
          .backgroundColor(AppColor.Brand)
          .fontColor(Color.White)
          .onClick(() => this.navStack.pop())
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: AppSpace.Lg })
    } else {
      Column({ space: AppSpace.Sm }) {
        Button(this.importing ? '导入中...' : '开始导入')
          .width('100%')
          .height(48)
          .backgroundColor(this.canImport() ? AppColor.Brand : '#CCCCCC')
          .fontColor(Color.White)
          .fontSize(AppFont.BodyL)
          .borderRadius(AppRadius.Md)
          .enabled(this.canImport() && !this.importing)
          .onClick(() => this.doImport())
        if (this.importing && this.progressText) {
          Text(this.progressText)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
        }
      }
      .width('100%')
    }
  }

  private canImport(): boolean {
    return this.pickedFiles.length > 0 && this.bookTitle.length > 0;
  }
}