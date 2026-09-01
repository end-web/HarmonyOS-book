import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { TextReadingSettings } from '../../model/TextReading';
import { ReaderPattern, normalizeHex } from '../../model/ReaderTheme';

const STORE_NAME: string = 'text_reading_settings';
const KEY_FONT_SIZE: string = 'font_size';
const KEY_LINE_HEIGHT: string = 'line_height';
const KEY_THEME_ID: string = 'theme_id';
const KEY_CUSTOM_BACKGROUND: string = 'custom_background';
const KEY_PATTERN: string = 'background_pattern';
const KEY_BACKGROUND_IMAGE: string = 'background_image';
const KEY_OVERLAY_ALPHA: string = 'overlay_alpha';

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
    const savedThemeId = store.getSync(KEY_THEME_ID, TextReadingSettings.THEME_DEFAULT);
    const savedBackground = store.getSync(KEY_CUSTOM_BACKGROUND, TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT);
    const savedPattern = store.getSync(KEY_PATTERN, ReaderPattern.None as string);
    const savedImage = store.getSync(KEY_BACKGROUND_IMAGE, '');
    const savedOverlay = store.getSync(KEY_OVERLAY_ALPHA, TextReadingSettings.OVERLAY_DEFAULT);
    const fontSize = typeof savedFontSize === 'number' ? savedFontSize : TextReadingSettings.FONT_SIZE_DEFAULT;
    const lineHeight = typeof savedLineHeight === 'number' ? savedLineHeight : TextReadingSettings.LINE_HEIGHT_DEFAULT;
    const themeId = typeof savedThemeId === 'string' ? savedThemeId : TextReadingSettings.THEME_DEFAULT;
    const background = typeof savedBackground === 'string'
      ? savedBackground : TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT;
    const pattern = typeof savedPattern === 'string' ? savedPattern : ReaderPattern.None as string;
    const image = typeof savedImage === 'string' ? savedImage : '';
    const overlay = typeof savedOverlay === 'number' ? savedOverlay : TextReadingSettings.OVERLAY_DEFAULT;
    return TextReadingSettings.ofAll(fontSize, lineHeight, themeId, background, pattern, image, overlay);
  }

  static async save(context: common.Context, settings: TextReadingSettings): Promise<void> {
    await TextReadingSettingsService.init(context);
    const store = TextReadingSettingsService.store;
    if (store === null) return;
    store.putSync(KEY_FONT_SIZE, TextReadingSettings.normalizeFontSize(settings.fontSize));
    store.putSync(KEY_LINE_HEIGHT, TextReadingSettings.normalizeLineHeight(settings.lineHeight));
    store.putSync(KEY_THEME_ID, TextReadingSettings.normalizeThemeId(settings.themeId));
    store.putSync(KEY_CUSTOM_BACKGROUND, normalizeHex(settings.customBackground));
    store.putSync(KEY_PATTERN, TextReadingSettings.normalizePattern(settings.pattern));
    store.putSync(KEY_BACKGROUND_IMAGE, settings.backgroundImage);
    store.putSync(KEY_OVERLAY_ALPHA, TextReadingSettings.normalizeOverlay(settings.overlayAlpha));
    await store.flush();
  }
}
