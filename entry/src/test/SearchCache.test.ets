import { describe, it, expect } from '@ohos/hypium';
import { Book, Chapter } from '../main/ets/model/Book';
import { SearchCache } from '../main/ets/utils/SearchCache';

function createBook(chapters: Chapter[], cover: string = ''): Book {
  const book: Book = {
    id: 'book-1',
    contentType: 'audio',
    title: 'Book',
    author: 'Author',
    narrator: 'Narrator',
    cover: cover,
    category: 'audio',
    intro: '',
    totalDuration: 0,
    chapterCount: chapters.length,
    rating: 0,
    tags: [],
    chapters: chapters,
    bookUrl: 'book-url',
    sourceUrl: 'source-url',
    variables: undefined,
    skipIntro: undefined,
    skipOutro: undefined
  };
  return book;
}

export default function searchCacheTest(): void {
  describe('SearchCache', () => {
    it('preserves hydrated chapters when metadata shell is cached', 0, () => {
      const chapter: Chapter = {
        id: 'book-1-c0',
        index: 1,
        title: 'Chapter 1',
        duration: 0,
        source: { type: 'url', value: 'chapter-url' },
        originSourceValue: 'chapter-url'
      };
      SearchCache.clear();
      SearchCache.put(createBook([chapter]));
      SearchCache.put(createBook([]));
      const cached = SearchCache.get('book-1');
      expect(cached === null ? 0 : cached.chapters.length).assertEqual(1);
      SearchCache.clear();
    });

    it('preserves a hydrated cover when a new search shell has no cover', 0, () => {
      SearchCache.clear();
      SearchCache.put(createBook([], 'https://image.example.com/book.jpg'));
      SearchCache.put(createBook([]));
      const cached = SearchCache.get('book-1');
      expect(cached === null ? '' : cached.cover)
        .assertEqual('https://image.example.com/book.jpg');
      SearchCache.clear();
    });
  });
}
