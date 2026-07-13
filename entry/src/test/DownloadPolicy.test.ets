import { describe, it, expect } from '@ohos/hypium';
import { DownloadPolicy, DownloadGenerationSnapshot } from '../main/ets/service/DownloadPolicy';
import { Chapter } from '../main/ets/model/Book';

export default function downloadPolicyTest() {
  describe('DownloadPolicy', () => {
    it('invalidates stale task generations after pause or delete', 0, () => {
      const captured: DownloadGenerationSnapshot = { global: 1, book: 2, chapter: 3 };
      expect(DownloadPolicy.isGenerationCurrent(captured, captured, false, false)).assertEqual(true);
      expect(DownloadPolicy.isGenerationCurrent(captured, { global: 1, book: 3, chapter: 3 }, false, false))
        .assertEqual(false);
      expect(DownloadPolicy.isGenerationCurrent(captured, captured, true, false)).assertEqual(false);
      expect(DownloadPolicy.isGenerationCurrent(captured, captured, false, true)).assertEqual(false);
    });

    it('prefers stable page url when matching chapters', 0, () => {
      expect(DownloadPolicy.matchesChapter('old-id', 'https://audio.test/page/1', 'new-id',
        'https://audio.test/page/1')).assertEqual(true);
      expect(DownloadPolicy.matchesChapter('same-id', 'https://audio.test/page/old', 'same-id', ''))
        .assertEqual(true);
    });

    it('rejects hls and non audio responses', 0, () => {
      expect(DownloadPolicy.isHls('https://audio.test/book.m3u8?token=1', '')).assertEqual(true);
      expect(DownloadPolicy.isHls('https://audio.test/play', 'application/vnd.apple.mpegurl')).assertEqual(true);
      expect(DownloadPolicy.isAllowedAudioContentType('audio/mpeg')).assertEqual(true);
      expect(DownloadPolicy.isAllowedAudioContentType('application/octet-stream')).assertEqual(true);
      expect(DownloadPolicy.isAllowedAudioContentType('text/html; charset=utf-8')).assertEqual(false);
    });

    it('uses the original http url for chapters currently backed by a local file', 0, () => {
      const chapter: Chapter = {
        id: 'chapter-1',
        index: 1,
        title: '第一章',
        duration: 0,
        source: { type: 'file', value: '/data/storage/audio.mp3' },
        originSourceValue: 'https://audio.test/chapter/1'
      };
      expect(DownloadPolicy.stablePageUrl(chapter)).assertEqual('https://audio.test/chapter/1');
      chapter.originSourceValue = '';
      expect(DownloadPolicy.stablePageUrl(chapter)).assertEqual('');
      chapter.source = { type: 'url', value: '../chapter/1,{"webView":true}' };
      expect(DownloadPolicy.stablePageUrl(chapter)).assertEqual('../chapter/1,{"webView":true}');
    });

    it('recognizes common audio signatures', 0, () => {
      const id3 = new Uint8Array([0x49, 0x44, 0x33, 0x04]).buffer;
      const mp3 = new Uint8Array([0xFF, 0xFB, 0x90, 0x64]).buffer;
      const html = new Uint8Array([0x3C, 0x68, 0x74, 0x6D]).buffer;
      expect(DownloadPolicy.hasKnownAudioSignature(id3)).assertEqual(true);
      expect(DownloadPolicy.hasKnownAudioSignature(mp3)).assertEqual(true);
      expect(DownloadPolicy.hasKnownAudioSignature(html)).assertEqual(false);
    });

    it('classifies stable download failure codes', 0, () => {
      expect(DownloadPolicy.classifyFailure('下载已取消')).assertEqual('cancelled');
      expect(DownloadPolicy.classifyFailure('暂不支持 HLS 音频离线下载')).assertEqual('unsupported_hls');
      expect(DownloadPolicy.classifyFailure('存储空间不足')).assertEqual('storage');
      expect(DownloadPolicy.classifyFailure('connect timeout')).assertEqual('network');
      expect(DownloadPolicy.classifyFailure('响应不是音频内容 text/html')).assertEqual('invalid_response');
    });
  });
}
