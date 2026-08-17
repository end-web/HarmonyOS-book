import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { TextReadingSettings } from '../../model/TextReading';

const STORE_NAME: string = 'text_reading_settings';
const KEY_FONT_SIZE: string = 'font_size';
const KEY_LINE_HEIGHT: string = 'line_height';

export class TextReadingSettingsService {
  private static store: preferences.Preferences | null = null;
  private static initPromise: Promise<void> | null = null;

  static init(context: common.Context): Promise<void> {
    if (TextReadingSettingsService.store !== null) return Promise.resolve();
    if (TextReadingSettingsService.initPromise !== null) return TextReadingSettingsService.initPromise;
    TextReadingSettingsService.initPromise = preferences.getPreferences(context, { name: STORE_NAME })
      .then((value: preferences.Preferences): void => {
        TextReadingSettingsService.store = value;
      })
      .finally((): void => {
        TextReadingSettingsService.initPromise = null;
      });
    return TextReadingSettingsService.initPromise;
  }

  static async get(context: common.Context): Promise<TextReadingSettings> {
    await TextReadingSettingsService.init(context);
    const store = TextReadingSettingsService.store;
    if (store === null) return new TextReadingSettings();
    const savedFontSize = store.getSync(KEY_FONT_SIZE, TextReadingSettings.FONT_SIZE_DEFAULT);
    const savedLineHeight = store.getSync(KEY_LINE_HEIGHT, TextReadingSettings.LINE_HEIGHT_DEFAULT);
    const fontSize = typeof savedFontSize === 'number' ? savedFontSize : TextReadingSettings.FONT_SIZE_DEFAULT;
    const lineHeight = typeof savedLineHeight === 'number' ? savedLineHeight : TextReadingSettings.LINE_HEIGHT_DEFAULT;
    return TextReadingSettings.of(fontSize, lineHeight);
  }

  static async save(context: common.Context, settings: TextReadingSettings): Promise<void> {
    await TextReadingSettingsService.init(context);
    const store = TextReadingSettingsService.store;
    if (store === null) return;
    store.putSync(KEY_FONT_SIZE, TextReadingSettings.normalizeFontSize(settings.fontSize));
    store.putSync(KEY_LINE_HEIGHT, TextReadingSettings.normalizeLineHeight(settings.lineHeight));
    await store.flush();
  }
}
