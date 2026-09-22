import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { bookParser } from '@hms.core.readerservice.bookParser';

/** 通过 ReaderKit 解包资源，再由 ImageKit 解码为独立封面，不保存解析器临时路径。 */
export class EpubCoverService {
  static async extract(handler: bookParser.BookParserHandler, directory: string): Promise<string> {
    const cover = handler.getBookInfo().bookCoverImage;
    if (cover === undefined || cover.length === 0) return '';
    try {
      // 不同 ReaderKit 版本可能返回解包后的沙箱文件，或 EPUB 内相对资源路径。
      if (cover.startsWith('/') || cover.startsWith('file://')) {
        const path = cover.startsWith('file://') ? cover.substring(7) : cover;
        if (await fileIo.access(path)) {
          const stat = await fileIo.stat(path);
          if (stat.size > 0 && stat.size <= 16 * 1024 * 1024) {
            return await EpubCoverService.decode(path, directory);
          }
        }
      }
      const count = Math.min(handler.getSpineList().length, 8);
      for (let index = 0; index < count; index++) {
        try {
          // ReaderKit 先加载 spine，资源查询才有相对路径上下文。
          await handler.getSpineItemContent(index);
          const href = handler.getSpineList()[index].href;
          const parent = href.substring(0, href.lastIndexOf('/') + 1);
          const candidates: string[] = [cover, EpubCoverService.relativePath(parent, cover)];
          const parts = cover.split('/');
          for (let part = 1; part < parts.length; part++) candidates.push(parts.slice(part).join('/'));
          for (const candidate of candidates) {
            try {
              const bytes = handler.getResourceContent(index, candidate);
              if (bytes === undefined || bytes.byteLength === 0 || bytes.byteLength > 16 * 1024 * 1024) continue;
              return await EpubCoverService.decode(bytes, directory);
            } catch (_e) { /* 继续兼容包内路径和章节相对路径。 */ }
          }
        } catch (_e) { /* 无效 spine 不影响其他候选。 */ }
      }
    } catch (_e) { /* 缺少或损坏的可选封面不阻断正文导入。 */ }
    return '';
  }

  private static relativePath(parent: string, target: string): string {
    const from = parent.split('/').filter((part: string): boolean => part.length > 0);
    const to = target.split('/').filter((part: string): boolean => part.length > 0);
    while (from.length > 0 && to.length > 0 && from[0] === to[0]) { from.shift(); to.shift(); }
    return '../'.repeat(from.length) + to.join('/');
  }

  private static async decode(input: string | ArrayBuffer, directory: string): Promise<string> {
    const source = typeof input === 'string' ? image.createImageSource(input) : image.createImageSource(input);
    let pixels: image.PixelMap | null = null;
    let packer: image.ImagePacker | null = null;
    let file: fileIo.File | null = null;
    const destination = `${directory}/cover.jpg`;
    try {
      const info = await source.getImageInfo();
      if (info.size.width <= 0 || info.size.height <= 0 || info.size.width * info.size.height > 64000000) return '';
      const scale = Math.min(1, 1200 / Math.max(info.size.width, info.size.height));
      pixels = await source.createPixelMap({ desiredSize: {
        width: Math.max(1, Math.round(info.size.width * scale)),
        height: Math.max(1, Math.round(info.size.height * scale))
      } });
      packer = image.createImagePacker();
      const encoded = await packer.packToData(pixels, { format: 'image/jpeg', quality: 90 });
      file = await fileIo.open(destination, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      let offset = 0;
      while (offset < encoded.byteLength) {
        const written = await fileIo.write(file.fd, encoded.slice(offset));
        if (written <= 0) throw new Error('Cover write interrupted');
        offset += written;
      }
      return destination;
    } finally {
      if (file !== null) await fileIo.close(file);
      if (packer !== null) await packer.release();
      if (pixels !== null) await pixels.release();
      await source.release();
    }
  }
}
