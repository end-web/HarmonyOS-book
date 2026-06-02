import { curves } from '@kit.ArkUI';

export class AppColor {
  static readonly Brand: string = '#0A59F7';
  static readonly BrandSoft: string = '#3B7BF9';
  static readonly BrandDark: string = '#084CD6';

  static readonly OnBrand: string = '#FFFFFF';

  static readonly GlassBg: string = '#33FFFFFF';
  static readonly GlassBgDark: string = '#33000000';
  static readonly GlassStroke: string = '#1FFFFFFF';

  static readonly Shadow: string = '#1A000000';
  static readonly Divider: string = '#1F000000';
}

export class AppRadius {
  static readonly Xs: number = 4;
  static readonly Sm: number = 8;
  static readonly Md: number = 12;
  static readonly Lg: number = 16;
  static readonly Xl: number = 24;
  static readonly Pill: number = 999;
}

export class AppSpace {
  static readonly Xxs: number = 4;
  static readonly Xs: number = 8;
  static readonly Sm: number = 12;
  static readonly Md: number = 16;
  static readonly Lg: number = 24;
  static readonly Xl: number = 32;
}

export class AppFont {
  static readonly Caption: number = 12;
  static readonly Body: number = 14;
  static readonly BodyL: number = 16;
  static readonly Title: number = 18;
  static readonly TitleL: number = 22;
  static readonly Display: number = 28;
}

export class AppMotion {
  static readonly Fast: number = 150;
  static readonly Base: number = 250;
  static readonly Standard: number = 250; // 标准动画时长（与 Base 相同）
  static readonly Slow: number = 350;
  static readonly Page: number = 380;
}

/**
 * 统一动效曲线 token
 * - Standard: 通用进出场（默认）
 * - Emphasized: 大幅位移/页面级强调
 * - Decelerate: 入场（慢出快进）
 * - Accelerate: 出场（快出慢进）
 * - Spring: 轻量弹簧（点选/Tab）
 * - SpringSoft: 柔性弹簧（Sheet/弹层）
 */
export class AppCurve {
  static readonly Standard = curves.cubicBezierCurve(0.2, 0, 0, 1);
  static readonly Emphasized = curves.cubicBezierCurve(0.33, 0, 0.1, 1);
  static readonly Decelerate = curves.cubicBezierCurve(0, 0, 0, 1);
  static readonly Accelerate = curves.cubicBezierCurve(0.4, 0, 1, 1);
  static readonly Spring = curves.springMotion(0.4, 0.85);
  static readonly SpringSoft = curves.springMotion(0.6, 0.9);
}
