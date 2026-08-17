import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { TextReadingPosition } from '../../model/TextReading';

const STORE_NAME: string = 'online_text_reading_progress';
const KEY_PREFIX: string = 'position_';

export class TextReadingProgressService {
  private static store: preferences.Preferences | null = null;
  private static initPromise: Promise<void> | null = null;

  static init(context: common.Context): Promise<void> {
    if (TextReadingProgressService.store !== null) return Promise.resolve();
    if (TextReadingProgressService.initPromise !== null) return TextReadingProgressService.initPromise;
    TextReadingProgressService.initPromise = preferences.getPreferences(context, { name: STORE_NAME })
      .then((value: preferences.Preferences): void => {
        TextReadingProgressService.store = value;
      })
      .finally((): void => {
        TextReadingProgressService.initPromise = null;
      });
    return TextReadingProgressService.initPromise;
  }

  static async get(context: common.Context, bookId: string): Promise<TextReadingPosition | null> {
    await TextReadingProgressService.init(context);
    const store = TextReadingProgressService.store;
    if (store === null) return null;
    const raw = store.getSync(TextReadingProgressService.key(bookId), '');
    if (typeof raw !== 'string' || !raw) return null;
    try {
      const parsed = JSON.parse(raw) as TextReadingPosition;
      const value = new TextReadingPosition();
      value.bookId = typeof parsed.bookId === 'string' ? parsed.bookId : bookId;
      value.resourceIndex = typeof parsed.resourceIndex === 'number' ? parsed.resourceIndex : 0;
      value.domPos = typeof parsed.domPos === 'string' ? parsed.domPos : '';
      value.charOffset = typeof parsed.charOffset === 'number' ? parsed.charOffset : 0;
      value.pageOffset = typeof parsed.pageOffset === 'number' ? parsed.pageOffset : 0;
      value.chapterTitle = typeof parsed.chapterTitle === 'string' ? parsed.chapterTitle : '';
      value.updatedAt = typeof parsed.updatedAt === 'number' ? parsed.updatedAt : 0;
      return value;
    } catch (_e) {
      return null;
    }
  }

  static async save(context: common.Context, position: TextReadingPosition): Promise<void> {
    await TextReadingProgressService.init(context);
    const store = TextReadingProgressService.store;
    if (store === null || !position.bookId) return;
    store.putSync(TextReadingProgressService.key(position.bookId), JSON.stringify(position));
    await store.flush();
  }

  static async remove(context: common.Context, bookId: string): Promise<void> {
    await TextReadingProgressService.init(context);
    const store = TextReadingProgressService.store;
    if (store === null) return;
    store.deleteSync(TextReadingProgressService.key(bookId));
    await store.flush();
  }

  private static key(bookId: string): string {
    return KEY_PREFIX + bookId.replace(new RegExp('[^A-Za-z0-9_.-]', 'g'), '_');
  }
}
