import { curves } from '@kit.ArkUI';
import lazy { uiMaterial } from '@kit.ArkUI';
import { AppAppearance } from '../model/AppAppearance';
import { PlatformCompat } from '../utils/PlatformCompat';

export class AppColor {
  static get Brand(): ResourceStr {
    const accent: string = AppAppearance.current.accent;
    return accent.length > 0 ? accent : $r('app.color.app_brand');
  }
  static get BrandHover(): ResourceStr {
    const accent: string = AppAppearance.current.accent;
    return accent.length > 0 ? AppAppearance.shade(accent, 0.92) : $r('app.color.app_brand_hover');
  }
  static get BrandPressed(): ResourceStr {
    const accent: string = AppAppearance.current.accent;
    return accent.length > 0 ? AppAppearance.shade(accent, 0.82) : $r('app.color.app_brand_pressed');
  }
  static get BrandDisabled(): ResourceStr {
    const accent: string = AppAppearance.current.accent;
    return accent.length > 0 ? '#66' + accent.substring(1) : $r('app.color.app_brand_disabled');
  }
  static get BrandSoft(): ResourceStr {
    const accent: string = AppAppearance.current.accent;
    return accent.length > 0 ? '#22' + accent.substring(1) : $r('app.color.app_brand_soft');
  }
  static get BrandDark(): ResourceStr {
    const accent: string = AppAppearance.current.accent;
    return accent.length > 0 ? AppAppearance.shade(accent, 0.78) : $r('app.color.app_brand_dark');
  }
  static get OnBrand(): ResourceStr {
    const accent: string = AppAppearance.current.accent;
    return accent.length > 0 ? AppAppearance.foreground(accent) : $r('app.color.app_on_brand');
  }
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

/** 原生材质统一入口；每次外观变更清空缓存，避免重复创建或保留旧光感色。 */
export class AppMaterial {
  private static cache: Map<string, uiMaterial.Material> = new Map<string, uiMaterial.Material>();
  private static appearanceKey: string = '';

  private static resolveStyle(fallback: uiMaterial.ImmersiveStyle): uiMaterial.ImmersiveStyle {
    switch (AppAppearance.current.material) {
      case 1: return uiMaterial.ImmersiveStyle.ULTRA_THIN;
      case 2: return uiMaterial.ImmersiveStyle.THIN;
      case 3: return uiMaterial.ImmersiveStyle.REGULAR;
      case 4: return uiMaterial.ImmersiveStyle.THICK;
      case 5: return uiMaterial.ImmersiveStyle.ULTRA_THICK;
      default: return fallback;
    }
  }

  private static material(key: string, fallback: uiMaterial.ImmersiveStyle,
    shadow: boolean, interactive: boolean, invert: boolean = false): uiMaterial.Material {
    const appearanceKey: string = AppAppearance.current.material.toString() + ':' + AppAppearance.current.accent;
    if (appearanceKey !== AppMaterial.appearanceKey) {
      AppMaterial.cache.clear();
      AppMaterial.appearanceKey = appearanceKey;
    }
    // Read the reactive brand token even on a cache hit, so mounted controls observe theme changes.
    const lightColor: ResourceColor = AppColor.Brand;
    const cached: uiMaterial.Material | undefined = AppMaterial.cache.get(key);
    if (cached !== undefined) return cached;
    const material: uiMaterial.Material = new uiMaterial.ImmersiveMaterial({
      style: AppMaterial.resolveStyle(fallback),
      applyShadow: shadow,
      interactive: interactive,
      colorInvert: invert,
      lightEffect: { color: lightColor }
    });
    AppMaterial.cache.set(key, material);
    return material;
  }

  static get InteractiveThin(): uiMaterial.Material | undefined {
    if (!PlatformCompat.immersiveMaterial) return undefined;
    return AppMaterial.material('interactiveThin', uiMaterial.ImmersiveStyle.THIN, false, true);
  }
  static get InteractiveClean(): uiMaterial.Material | undefined {
    if (!PlatformCompat.immersiveMaterial) return undefined;
    return AppMaterial.material('interactiveClean', uiMaterial.ImmersiveStyle.THIN, false, true, true);
  }
  static get SurfaceClean(): uiMaterial.Material | undefined {
    if (!PlatformCompat.immersiveMaterial) return undefined;
    return AppMaterial.material('surfaceClean', uiMaterial.ImmersiveStyle.THIN, false, false);
  }
  static get FloatingControl(): uiMaterial.Material | undefined {
    if (!PlatformCompat.immersiveMaterial) return undefined;
    return AppMaterial.material('floating', uiMaterial.ImmersiveStyle.ULTRA_THIN, true, true);
  }
  static get Sheet(): uiMaterial.Material | undefined {
    if (!PlatformCompat.immersiveMaterial) return undefined;
    return AppMaterial.material('sheet', uiMaterial.ImmersiveStyle.THIN, true, false);
  }
  static get PlayerSheet(): uiMaterial.Material | undefined {
    return AppMaterial.Sheet;
  }
  static get DialogUltraThick(): uiMaterial.Material | undefined {
    if (!PlatformCompat.immersiveMaterial) return undefined;
    return AppMaterial.material('dialog', uiMaterial.ImmersiveStyle.ULTRA_THICK, true, false);
  }
  static get SurfaceRegular(): uiMaterial.Material | undefined {
    if (!PlatformCompat.immersiveMaterial) return undefined;
    return AppMaterial.material('regular', uiMaterial.ImmersiveStyle.REGULAR, true, false);
  }

  static get SheetBackground(): ResourceColor {
    return PlatformCompat.immersiveMaterial ? Color.Transparent : $r('sys.color.comp_background_primary');
  }

  static get SheetBlur(): BlurStyle | undefined {
    return PlatformCompat.immersiveMaterial ? undefined : AppMaterial.fallbackBlur;
  }

  private static get fallbackBlur(): BlurStyle {
    switch (AppAppearance.current.material) {
      case 1: return BlurStyle.COMPONENT_ULTRA_THIN;
      case 2: return BlurStyle.COMPONENT_THIN;
      case 4: return BlurStyle.COMPONENT_THICK;
      case 5: return BlurStyle.COMPONENT_ULTRA_THICK;
      default: return BlurStyle.COMPONENT_REGULAR;
    }
  }

  static modifier(material: uiMaterial.Material | undefined,
    fallbackColor: ResourceColor = AppColor.GlassControlFallback): CompatibleMaterialModifier {
    return new CompatibleMaterialModifier(material, fallbackColor, AppMaterial.fallbackBlur);
  }
}

/** API 20 使用背景色和磨砂；旧设备不调用 systemMaterial，也不加载 uiMaterial。 */
class CompatibleMaterialModifier implements AttributeModifier<CommonAttribute> {
  private material: uiMaterial.Material | undefined;
  private fallbackColor: ResourceColor;
  private blur: BlurStyle;

  constructor(material: uiMaterial.Material | undefined, fallbackColor: ResourceColor, blur: BlurStyle) {
    this.material = material;
    this.fallbackColor = fallbackColor;
    this.blur = blur;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    if (PlatformCompat.immersiveMaterial && this.material !== undefined) {
      instance.systemMaterial(this.material);
    } else {
      instance.backgroundColor(this.fallbackColor).backgroundBlurStyle(this.blur);
    }
  }
}

/**
 * System blur presets used by the current frosted-glass surfaces.
 * Legacy blur options for surfaces that do not use native sheet materials.
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
  static get Accent(): ResourceStr {
    return AppAppearance.current.accent.length > 0 ? AppColor.Brand : $r('app.color.home_accent');
  }
  static get AccentSoft(): ResourceStr {
    return AppAppearance.current.accent.length > 0 ? AppColor.BrandSoft : $r('app.color.home_accent_soft');
  }
  static readonly TopControlTint: Resource = $r('app.color.home_top_control_tint');
  static readonly CardSurface: Resource = $r('app.color.home_card_surface');
  static readonly CardShadow: Resource = $r('app.color.home_card_shadow');
  static readonly ProgressTrack: Resource = $r('app.color.home_progress_track');
}
