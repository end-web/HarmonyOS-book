import { curves, uiMaterial } from '@kit.ArkUI';

export class AppColor {
  static readonly Brand: Resource = $r('app.color.app_brand');
  static readonly BrandHover: Resource = $r('app.color.app_brand_hover');
  static readonly BrandPressed: Resource = $r('app.color.app_brand_pressed');
  static readonly BrandDisabled: Resource = $r('app.color.app_brand_disabled');
  static readonly BrandSoft: Resource = $r('app.color.app_brand_soft');
  static readonly BrandDark: Resource = $r('app.color.app_brand_dark');
  static readonly OnBrand: Resource = $r('app.color.app_on_brand');
  static readonly Divider: Resource = $r('app.color.app_divider');
  static readonly Shadow: Resource = $r('app.color.app_shadow');
  static readonly GlassControlFallback: Resource = $r('app.color.glass_control_fallback');
  static readonly GlassSheetFallback: Resource = $r('app.color.glass_sheet_fallback');
  static readonly GlassControlTint: Resource = $r('app.color.glass_control_tint');
  static readonly GlassSheetControlTint: Resource = $r('app.color.glass_sheet_control_tint');
  static readonly GlassSheetStroke: Resource = $r('app.color.glass_sheet_stroke');
  static readonly GlassTextPrimary: Resource = $r('app.color.glass_text_primary');
  static readonly GlassTextSecondary: Resource = $r('app.color.glass_text_secondary');
  static readonly GlassTextTertiary: Resource = $r('app.color.glass_text_tertiary');
  static readonly GlassDivider: Resource = $r('app.color.glass_divider');
  static readonly GlassStroke: Resource = $r('app.color.glass_stroke');
  static readonly GlassShadow: Resource = $r('app.color.glass_shadow');

  // Legacy literal overlays retained for existing call sites.
  static readonly GlassBg: string = '#33FFFFFF';
  static readonly GlassBgDark: string = '#33000000';
}

const APP_LIGHT_EFFECT: uiMaterial.LightEffectOptions = {
  color: AppColor.Brand
};

/** HarmonyOS 7 immersive material presets shared by floating controls and sheets. */
export class AppMaterial {
  static readonly InteractiveThin: uiMaterial.Material = new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.THIN,
    applyShadow: false,
    interactive: true
  });

  static readonly InteractiveClean: uiMaterial.Material = new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.THIN,
    colorInvert: true,
    applyShadow: false,
    interactive: true,
    lightEffect: APP_LIGHT_EFFECT
  });

  static readonly SurfaceClean: uiMaterial.Material = new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.THIN,
    applyShadow: false
  });

  static readonly FloatingControl: uiMaterial.Material = new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
    applyShadow: true,
    interactive: true,
    lightEffect: APP_LIGHT_EFFECT
  });

  static readonly DialogUltraThick: uiMaterial.Material = new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.ULTRA_THICK,
    applyShadow: true,
    lightEffect: APP_LIGHT_EFFECT
  });

  static readonly SurfaceRegular: uiMaterial.Material = new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.REGULAR,
    materialColor: AppColor.BrandSoft,
    applyShadow: true
  });
}

/**
 * System blur presets used by the current frosted-glass surfaces.
 * AppMaterial stays available so immersive material can be restored when the platform re-enables it.
 */
export class AppGlass {
  static readonly ControlBlur: BlurStyle = BlurStyle.BACKGROUND_THIN;
  static readonly SheetBlur: BlurStyle = BlurStyle.BACKGROUND_REGULAR;

  static readonly ControlOptions: BackgroundBlurStyleOptions = {
    colorMode: ThemeColorMode.SYSTEM,
    adaptiveColor: AdaptiveColor.AVERAGE,
    scale: 0.62,
    policy: BlurStyleActivePolicy.FOLLOWS_WINDOW_ACTIVE_STATE,
    inactiveColor: AppColor.GlassControlFallback
  };

  static readonly SheetOptions: BackgroundBlurStyleOptions = {
    colorMode: ThemeColorMode.DARK,
    adaptiveColor: AdaptiveColor.AVERAGE,
    scale: 0.65,
    policy: BlurStyleActivePolicy.FOLLOWS_WINDOW_ACTIVE_STATE,
    inactiveColor: AppColor.GlassSheetFallback
  };

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

/**
 * 首页与记录页共用的暖色主题。
 * 走 base/dark element/color.json 双份资源，自动深浅切换。
 */
export class HomeTheme {
  static readonly BgWarmTop: Resource = $r('app.color.home_bg_warm_top');
  static readonly BgWarmMid: Resource = $r('app.color.home_bg_warm_mid');
  static readonly BgNeutral: Resource = $r('app.color.home_bg_neutral');
  /** 状态栏窄条：与 BgNeutral 同色半透明，配合 backdropBlur */
  static readonly StatusScrim: Resource = $r('app.color.home_status_scrim');
  static readonly Accent: Resource = $r('app.color.home_accent');
  static readonly AccentSoft: Resource = $r('app.color.home_accent_soft');
  static readonly TopControlTint: Resource = $r('app.color.home_top_control_tint');
  static readonly CardSurface: Resource = $r('app.color.home_card_surface');
  static readonly CardShadow: Resource = $r('app.color.home_card_shadow');
  static readonly ProgressTrack: Resource = $r('app.color.home_progress_track');
}
