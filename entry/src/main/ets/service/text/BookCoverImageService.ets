import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';

/** Decode embedded ebook covers to a bounded, durable JPEG thumbnail. */
export class BookCoverImageService {
  static async decode(input: string | ArrayBuffer, directory: string): Promise<string> {
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
