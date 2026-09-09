/** App 外观偏好。阅读纸张主题独立保存，不随 App 强调色变化。 */
@ObservedV2
export class AppAppearance {
  private static singleton: AppAppearance | null = null;

  static get current(): AppAppearance {
    if (AppAppearance.singleton === null) {
      AppAppearance.singleton = new AppAppearance();
    }
    return AppAppearance.singleton;
  }

  /** 0 为各控件默认材质，1–5 对应超薄至超厚。 */
  @Trace material: number = 0;
  /** 空字符串表示使用随深浅模式变化的默认品牌色。 */
  @Trace accent: string = '';

  static normalizeMaterial(value: number): number {
    return Number.isInteger(value) && value >= 0 && value <= 5 ? value : 0;
  }

  static normalizeAccent(value: string): string {
    const hex: string = value.trim().toUpperCase();
    return /^#[0-9A-F]{6}$/.test(hex) ? hex : '';
  }

  static shade(hex: string, scale: number): string {
    const red: number = Math.round(parseInt(hex.substring(1, 3), 16) * scale);
    const green: number = Math.round(parseInt(hex.substring(3, 5), 16) * scale);
    const blue: number = Math.round(parseInt(hex.substring(5, 7), 16) * scale);
    return '#' + red.toString(16).padStart(2, '0') + green.toString(16).padStart(2, '0') +
      blue.toString(16).padStart(2, '0');
  }

  static foreground(hex: string): string {
    const red: number = parseInt(hex.substring(1, 3), 16);
    const green: number = parseInt(hex.substring(3, 5), 16);
    const blue: number = parseInt(hex.substring(5, 7), 16);
    return red * 0.299 + green * 0.587 + blue * 0.114 > 165 ? '#191919' : '#FFFFFF';
  }
}
