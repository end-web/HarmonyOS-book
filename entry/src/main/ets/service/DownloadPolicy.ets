import { Chapter } from '../model/Book';

export interface DownloadGenerationSnapshot {
  global: number;
  book: number;
  chapter: number;
}

export type DownloadFailureCode = 'network' | 'storage' | 'invalid_response'
  | 'unsupported_hls' | 'cancelled' | 'unknown';

export class DownloadPolicy {
  static stablePageUrl(chapter: Chapter): string {
    const origin = chapter.originSourceValue || '';
    if (origin && !DownloadPolicy.isLocalPath(origin)) return origin;
    if (chapter.source.type === 'url' && chapter.source.value && !DownloadPolicy.isLocalPath(chapter.source.value)) {
      return chapter.source.value;
    }
    return '';
  }

  static isHttpUrl(url: string): boolean {
    const lower = (url || '').toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  static isLocalPath(value: string): boolean {
    const lower = (value || '').trim().toLowerCase();
    return lower.startsWith('/') || lower.startsWith('file://') || lower.startsWith('rawfile://');
  }

  static isGenerationCurrent(snapshot: DownloadGenerationSnapshot, current: DownloadGenerationSnapshot,
    paused: boolean, deleted: boolean): boolean {
    return snapshot.global === current.global && snapshot.book === current.book
      && snapshot.chapter === current.chapter && !paused && !deleted;
  }

  static generationToken(snapshot: DownloadGenerationSnapshot): string {
    return `${snapshot.global}:${snapshot.book}:${snapshot.chapter}`;
  }

  static taskKey(bookId: string, pageUrl: string): string {
    return `${bookId}|${pageUrl}`;
  }

  static matchesChapter(chapterId: string, pageUrl: string, targetChapterId: string,
    targetPageUrl: string): boolean {
    if (targetPageUrl && pageUrl === targetPageUrl) return true;
    return chapterId === targetChapterId;
  }

  static isHls(url: string, contentType: string): boolean {
    const cleanUrl = url.toLowerCase().split('?')[0];
    const type = contentType.toLowerCase();
    return cleanUrl.endsWith('.m3u8') || type.includes('mpegurl');
  }

  static isAllowedAudioContentType(contentType: string): boolean {
    if (!contentType) return true;
    const type = contentType.toLowerCase().split(';')[0].trim();
    if (type.startsWith('audio/')) return true;
    return type === 'application/octet-stream' || type === 'binary/octet-stream'
      || type === 'application/mp4' || type === 'video/mp4';
  }

  static needsAudioSignatureCheck(contentType: string): boolean {
    if (!contentType) return true;
    const type = contentType.toLowerCase().split(';')[0].trim();
    return type === 'application/octet-stream' || type === 'binary/octet-stream';
  }

  static hasKnownAudioSignature(buffer: ArrayBuffer): boolean {
    const bytes = new Uint8Array(buffer);
    if (bytes.length < 4) return false;
    if (DownloadPolicy.matchesAscii(bytes, 0, 'ID3') || DownloadPolicy.matchesAscii(bytes, 0, 'fLaC')
      || DownloadPolicy.matchesAscii(bytes, 0, 'OggS')) return true;
    if (DownloadPolicy.matchesAscii(bytes, 0, 'RIFF') && DownloadPolicy.matchesAscii(bytes, 8, 'WAVE')) return true;
    if (bytes.length >= 8 && DownloadPolicy.matchesAscii(bytes, 4, 'ftyp')) return true;
    if (bytes[0] === 0xFF && (bytes[1] & 0xE0) === 0xE0) return true;
    return false;
  }

  static classifyFailure(message: string): DownloadFailureCode {
    const lower = (message || '').toLowerCase();
    if (lower.includes('取消') || lower.includes('cancel')) return 'cancelled';
    if (lower.includes('hls') || lower.includes('m3u8') || lower.includes('mpegurl')) return 'unsupported_hls';
    if (lower.includes('空间') || lower.includes('目录') || lower.includes('存储')
      || lower.includes('enospc') || lower.includes('no space')) return 'storage';
    if (lower.includes('响应不是音频') || lower.includes('文件过小') || lower.includes('文件头')
      || lower.includes('下载不完整') || lower.includes('写入不完整') || lower.includes('http ')
      || lower.includes('下载失败 4') || lower.includes('下载失败 5')) return 'invalid_response';
    if (lower.includes('timeout') || lower.includes('timed out') || lower.includes('network')
      || lower.includes('socket') || lower.includes('connect') || lower.includes('econn')
      || lower.includes('网络')) return 'network';
    return 'unknown';
  }

  static failureText(code: DownloadFailureCode): string {
    if (code === 'network') return '网络中断，请稍后重试';
    if (code === 'storage') return '存储空间不足或目录不可用';
    if (code === 'invalid_response') return '下载响应不是有效音频';
    if (code === 'unsupported_hls') return '暂不支持 HLS 音频离线下载';
    if (code === 'cancelled') return '下载已取消';
    return '下载失败，请重试';
  }

  private static matchesAscii(bytes: Uint8Array, offset: number, value: string): boolean {
    if (offset < 0 || bytes.length < offset + value.length) return false;
    for (let i = 0; i < value.length; i++) {
      if (bytes[offset + i] !== value.charCodeAt(i)) return false;
    }
    return true;
  }
}
