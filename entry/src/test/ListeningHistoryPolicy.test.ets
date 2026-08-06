import { describe, it, expect } from '@ohos/hypium';
import { ListeningHistoryPolicy, ListeningRecordCandidate } from '../main/ets/service/ListeningHistoryPolicy';
import { BookIdentity } from '../main/ets/utils/BookIdentity';

function candidate(bookId: string, sourceUrl: string, bookUrl: string, hasBook: boolean): ListeningRecordCandidate {
  const item = new ListeningRecordCandidate(bookId);
  if (hasBook) item.setBook(sourceUrl, bookUrl, '测试书籍', '测试作者', 'cover');
  return item;
}

export default function listeningHistoryPolicyTest(): void {
  describe('ListeningHistoryPolicy', () => {
    it('generates one online id for home and search entries', 0, () => {
      const homeId = BookIdentity.onlineAudioBookId('builtin://source', 'book/100');
      const searchId = BookIdentity.onlineAudioBookId('builtin://source', 'book/100');
      expect(homeId).assertEqual(searchId);
      expect(homeId.startsWith('search_audio_')).assertEqual(true);
    });

    it('merges legacy aliases and keeps the latest playback progress', 0, () => {
      const oldItem = candidate('home_audio_same', '', '', false);
      oldItem.addStats(30, 100, '旧书名', '', '');
      oldItem.setHistory('home_audio_same-c2', '第三集', 1200, 5000, 100);
      const newItem = candidate('search_audio_same', 'builtin://source', 'book/100', true);
      newItem.addStats(40, 200, '测试书籍', '测试作者', 'cover');
      newItem.setProgress('search_audio_same-c4', '第五集', 3200, 8000, 4, 300);

      const merged = ListeningHistoryPolicy.merge([oldItem, newItem]);

      expect(merged.length).assertEqual(1);
      expect(merged[0].bookId).assertEqual('search_audio_same');
      expect(merged[0].aliasBookIds.length).assertEqual(2);
      expect(merged[0].listenSeconds).assertEqual(70);
      expect(merged[0].chapterId).assertEqual('search_audio_same-c4');
      expect(merged[0].progressMs).assertEqual(3200);
      expect(merged[0].updatedAt).assertEqual(300);
    });

    it('merges changed ids when source and book urls match', 0, () => {
      const first = candidate('legacy-id', 'builtin://source', 'book/100', true);
      const second = candidate('current-id', 'builtin://source', 'book/100', true);
      expect(ListeningHistoryPolicy.merge([first, second]).length).assertEqual(1);
    });

    it('does not merge known books with different source identities', 0, () => {
      const first = candidate('home_audio_collision', 'builtin://source', 'book/100', true);
      const second = candidate('search_audio_collision', 'builtin://source', 'book/200', true);
      expect(ListeningHistoryPolicy.merge([first, second]).length).assertEqual(2);
    });

    it('rebases legacy chapter ids to the retained book id', 0, () => {
      expect(BookIdentity.rebaseChapterId('home_audio_same-c8', 'home_audio_same', 'search_audio_same'))
        .assertEqual('search_audio_same-c8');
      expect(BookIdentity.chapterIndexFromId('search_audio_same-c8')).assertEqual(8);
    });

    it('merges record with source identity and record without via derived id', 0, () => {
      const derivedId = BookIdentity.onlineAudioBookId('builtin://source', 'book/200');
      const oldItem = candidate(derivedId, '', '', false);
      oldItem.addStats(20, 100, '旧记录', '', '');
      const newItem = candidate('some_other_id', 'builtin://source', 'book/200', false);
      newItem.addStats(30, 200, '新记录', '', '', 'builtin://source', 'book/200');
      const merged = ListeningHistoryPolicy.merge([oldItem, newItem]);
      expect(merged.length).assertEqual(1);
      expect(merged[0].listenSeconds).assertEqual(50);
    });

    it('does not merge when one side has source identity that maps to a different book', 0, () => {
      const oldItem = candidate('search_audio_unrelated', '', '', false);
      oldItem.addStats(10, 100, '无关旧记录', '', '');
      const newItem = candidate('another_id', 'builtin://source', 'book/999', false);
      newItem.addStats(20, 200, '新记录', '', '', 'builtin://source', 'book/999');
      const merged = ListeningHistoryPolicy.merge([oldItem, newItem]);
      expect(merged.length).assertEqual(2);
    });
  });
}
