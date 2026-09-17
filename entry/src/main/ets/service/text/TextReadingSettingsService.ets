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
const KEY_PAGE_TURN_MODE: string = 'page_turn_mode';
const KEY_SHOW_READING_STATUS: string = 'show_reading_status';

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
    const savedPattern = store.getSync(KEY_PATTERN, ReaderPattern.None);
    const savedImage = store.getSync(KEY_BACKGROUND_IMAGE, '');
    const savedOverlay = store.getSync(KEY_OVERLAY_ALPHA, TextReadingSettings.OVERLAY_DEFAULT);
    const savedPageTurnMode = store.getSync(KEY_PAGE_TURN_MODE, TextReadingSettings.PAGE_TURN_MODE_DEFAULT);
    const savedReadingStatus = store.getSync(KEY_SHOW_READING_STATUS, TextReadingSettings.SHOW_READING_STATUS_DEFAULT);
    const fontSize = typeof savedFontSize === 'number' ? savedFontSize : TextReadingSettings.FONT_SIZE_DEFAULT;
    const lineHeight = typeof savedLineHeight === 'number' ? savedLineHeight : TextReadingSettings.LINE_HEIGHT_DEFAULT;
    const themeId = typeof savedThemeId === 'string' ? savedThemeId : TextReadingSettings.THEME_DEFAULT;
    const background = typeof savedBackground === 'string'
      ? savedBackground : TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT;
    const pattern = typeof savedPattern === 'string' ? savedPattern : ReaderPattern.None;
    const image = typeof savedImage === 'string' ? savedImage : '';
    const overlay = typeof savedOverlay === 'number' ? savedOverlay : TextReadingSettings.OVERLAY_DEFAULT;
    const pageTurnMode = typeof savedPageTurnMode === 'string' ? savedPageTurnMode : TextReadingSettings.PAGE_TURN_MODE_DEFAULT;
    const showReadingStatus = typeof savedReadingStatus === 'boolean' ? savedReadingStatus :
      TextReadingSettings.SHOW_READING_STATUS_DEFAULT;
    const result = TextReadingSettings.ofAll(fontSize, lineHeight, themeId, background, pattern, image, overlay,
      pageTurnMode, showReadingStatus);
    result.followSystemTheme = store.getSync('follow_system_theme', false) === true;
    const marginLeft = store.getSync('marginLeft', 16);
    result.marginLeft = TextReadingSettings.normalizeMargin(typeof marginLeft === 'number' ? marginLeft : 16, 16);
    const marginRight = store.getSync('marginRight', 16);
    result.marginRight = TextReadingSettings.normalizeMargin(typeof marginRight === 'number' ? marginRight : 16, 16);
    const marginTop = store.getSync('marginTop', 12);
    result.marginTop = TextReadingSettings.normalizeMargin(typeof marginTop === 'number' ? marginTop : 12, 12,
      TextReadingSettings.MARGIN_MAX_LIMIT);
    const marginBottom = store.getSync('marginBottom', 12);
    result.marginBottom = TextReadingSettings.normalizeMargin(typeof marginBottom === 'number' ? marginBottom : 12, 12);
    return result;
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
    store.putSync(KEY_PAGE_TURN_MODE, TextReadingSettings.normalizePageTurnMode(settings.pageTurnMode));
    store.putSync(KEY_SHOW_READING_STATUS, settings.showReadingStatus);
    store.putSync('follow_system_theme', settings.followSystemTheme);
    store.putSync('marginLeft', TextReadingSettings.normalizeMargin(settings.marginLeft, 16));
    store.putSync('marginRight', TextReadingSettings.normalizeMargin(settings.marginRight, 16));
    store.putSync('marginTop', TextReadingSettings.normalizeMargin(settings.marginTop, 12,
      TextReadingSettings.MARGIN_MAX_LIMIT));
    store.putSync('marginBottom', TextReadingSettings.normalizeMargin(settings.marginBottom, 12));
    await store.flush();
  }
}
