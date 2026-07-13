import { fileIo, statfs } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { DownloadPolicy } from './DownloadPolicy';

const MIN_AUDIO_FILE_BYTES = 1024;
const MIN_FREE_BYTES = 16 * 1024 * 1024;
const FREE_SPACE_RESERVE_BYTES = 8 * 1024 * 1024;

export interface AudioDownloadRequest {
  url: string;
  headers: Record<string, string>;
  finalPath: string;
}

export class AudioDownloadTransport {
  private request: http.HttpRequest | null = null;
  private cancelled: boolean = false;

  cancel(): void {
    this.cancelled = true;
    if (this.request) {
      this.request.destroy();
    }
  }

  async download(options: AudioDownloadRequest): Promise<number> {
    const partPath = `${options.finalPath}.part`;
    let file: fileIo.File | null = null;
    let writeChain: Promise<void> = Promise.resolve();
    let writeErrorMessage = '';
    let writtenBytes = 0;
    let responseHeaders: Record<string, string> = {};
    let firstBytes: ArrayBuffer = new ArrayBuffer(0);
    let completed = false;

    this.cancelled = false;
    await AudioDownloadTransport.deleteFile(partPath);
    try {
      if (DownloadPolicy.isHls(options.url, '')) {
        throw new Error('暂不支持 HLS 音频离线下载');
      }
      AudioDownloadTransport.ensureFreeSpace(options.finalPath, MIN_FREE_BYTES);
      file = await fileIo.open(partPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      this.request = http.createHttp();
      this.request.on('headersReceive', (headers: Object) => {
        responseHeaders = AudioDownloadTransport.toHeaderRecord(headers);
        const contentLength = Number(AudioDownloadTransport.getHeader(responseHeaders, 'content-length'));
        if (contentLength > 0) {
          try {
            AudioDownloadTransport.ensureFreeSpace(options.finalPath, contentLength + FREE_SPACE_RESERVE_BYTES);
          } catch (err) {
            writeErrorMessage = err instanceof Error ? err.message : String(err);
            if (this.request) this.request.destroy();
          }
        }
      });
      this.request.on('dataReceive', (chunk: ArrayBuffer) => {
        if (this.cancelled || writeErrorMessage.length > 0 || chunk.byteLength === 0) return;
        if (firstBytes.byteLength === 0) firstBytes = AudioDownloadTransport.copyPrefix(chunk, 16);
        writeChain = writeChain.then(async (): Promise<void> => {
          if (this.cancelled || writeErrorMessage.length > 0 || !file) return;
          const count = await fileIo.write(file.fd, chunk, { offset: 0, length: chunk.byteLength });
          if (count !== chunk.byteLength) {
            throw new Error(`音频文件写入不完整 ${count}/${chunk.byteLength}`);
          }
          writtenBytes += count;
        }).catch((err: Error): void => {
          writeErrorMessage = err.message;
          if (this.request) this.request.destroy();
        });
      });

      let responseCode = 0;
      try {
        responseCode = await this.request.requestInStream(options.url, {
          method: http.RequestMethod.GET,
          header: options.headers,
          connectTimeout: 15000,
          readTimeout: 60000,
          usingCache: false
        });
      } catch (err) {
        await writeChain;
        if (writeErrorMessage.length > 0) throw new Error(writeErrorMessage);
        if (this.cancelled) throw new Error('下载已取消');
        throw new Error(err instanceof Error ? err.message : String(err));
      }
      await writeChain;
      if (writeErrorMessage.length > 0) throw new Error(writeErrorMessage);
      if (this.cancelled) throw new Error('下载已取消');
      if (responseCode !== 200) throw new Error(`下载失败 ${responseCode}`);

      const contentType = AudioDownloadTransport.getHeader(responseHeaders, 'content-type');
      if (DownloadPolicy.isHls(options.url, contentType)) {
        throw new Error('暂不支持 HLS 音频离线下载');
      }
      if (!DownloadPolicy.isAllowedAudioContentType(contentType)) {
        throw new Error(`响应不是音频内容${contentType ? ` (${contentType})` : ''}`);
      }
      const contentLength = Number(AudioDownloadTransport.getHeader(responseHeaders, 'content-length'));
      if (contentLength > 0 && writtenBytes !== contentLength) {
        throw new Error(`音频下载不完整 ${writtenBytes}/${contentLength}`);
      }
      if (writtenBytes <= MIN_AUDIO_FILE_BYTES) {
        throw new Error(`音频文件过小 (${writtenBytes} bytes)`);
      }
      if (DownloadPolicy.needsAudioSignatureCheck(contentType)
        && !DownloadPolicy.hasKnownAudioSignature(firstBytes)) {
        throw new Error('响应没有有效音频文件头');
      }

      if (file) {
        try { await fileIo.fsync(file.fd); } catch (_e) { /* best effort */ }
        await fileIo.close(file);
        file = null;
      }
      if (this.cancelled) throw new Error('下载已取消');
      await AudioDownloadTransport.deleteFile(options.finalPath);
      if (this.cancelled) throw new Error('下载已取消');
      await fileIo.moveFile(partPath, options.finalPath);
      completed = true;
      return writtenBytes;
    } finally {
      if (file) {
        try { await fileIo.close(file); } catch (_e) { /* ignore */ }
      }
      if (this.request) {
        this.request.destroy();
        this.request = null;
      }
      if (!completed) await AudioDownloadTransport.deleteFile(partPath);
    }
  }

  private static toHeaderRecord(headers: Object): Record<string, string> {
    const record = headers as Record<string, Object>;
    const result: Record<string, string> = {};
    for (const key of Object.keys(record)) {
      const value = record[key];
      if (value !== undefined && value !== null) result[key] = String(value);
    }
    return result;
  }

  private static getHeader(headers: Record<string, string>, name: string): string {
    const lower = name.toLowerCase();
    for (const key of Object.keys(headers)) {
      if (key.toLowerCase() === lower) return headers[key] || '';
    }
    return '';
  }

  private static async deleteFile(path: string): Promise<void> {
    try {
      if (await fileIo.access(path)) await fileIo.unlink(path);
    } catch (_e) {
      // File does not exist or has already been removed.
    }
  }

  private static ensureFreeSpace(filePath: string, requiredBytes: number): void {
    const slash = filePath.lastIndexOf('/');
    const dir = slash > 0 ? filePath.substring(0, slash) : filePath;
    try {
      const freeBytes = statfs.getFreeSizeSync(dir);
      if (freeBytes < requiredBytes) {
        throw new Error(`存储空间不足，需要 ${requiredBytes} bytes，剩余 ${freeBytes} bytes`);
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      if (message.includes('存储空间不足')) throw new Error(message);
      throw new Error(`下载目录不可用: ${message}`);
    }
  }

  private static copyPrefix(buffer: ArrayBuffer, maxLength: number): ArrayBuffer {
    const source = new Uint8Array(buffer);
    const length = Math.min(source.length, maxLength);
    const copy = new Uint8Array(length);
    for (let i = 0; i < length; i++) copy[i] = source[i];
    return copy.buffer;
  }
}
