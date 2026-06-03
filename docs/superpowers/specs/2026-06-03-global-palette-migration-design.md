# 全局色板迁移 + 按钮系统设计稿

> **目标**：把 `AppColor.Brand`（蓝 `#0A59F7`）从 9 个文件 50+ 处的字面 hex 引用统一切到资源限定符暖橙 `#FF6B3D`，**全局深浅模式适配**，新增 `AppButton` 组件统一所有 CTA 按钮的状态系统（Primary/Secondary/Ghost × Default/Pressed/Disabled/Loading）。

## 已决策项

| 维度 | 决策 |
|---|---|
| 迁移范围 | **全局换暖橙**：所有 `AppColor.Brand` 引用切到资源限定符；按钮、Slider、Tab、选中态、加载圈一并切 |
| 深浅模式 | **资源限定符自动切换**：`base/element/color.json` + `dark/element/color.json` 双份，与首页改版同套机制 |
| PlayerPage 例外 | **封面取色那套不动**：`accentColor` / `blurColor` / `ColorPickerUtils.darken` 等封面派生色保持原状；只切 13 处 `AppColor.Brand` 字面引用 |
| 按钮系统 | **完整状态**：3 variant（Primary/Secondary/Ghost）× 4 state（Default/Pressed/Disabled/Loading），封装 `AppButton` 组件 |
| 色板饱和度 | **A · 标准饱和度**：跟首页 `HomeTheme.Accent` 一致，`#FF6B3D`（浅）/ `#FF8A5A`（深） |

---

## 1. 颜色 token 落地

### 1.1 新增 token（base + dark 两份）

写入 `entry/src/main/resources/base/element/color.json` 与 `entry/src/main/resources/dark/element/color.json`。

| token | base (浅色) | dark (深色) | 用途 |
|---|---|---|---|
| `app_brand` | `#FF6B3D` | `#FF8A5A` | 主品牌色（替代 `AppColor.Brand`） |
| `app_brand_hover` | `#FF8559` | `#FFA078` | hover / 焦点态（暂未用，预留） |
| `app_brand_pressed` | `#E55520` | `#E0764A` | 按下态 |
| `app_brand_disabled` | `#FFD0BC` | `#5C3F2F` | 禁用态 |
| `app_brand_soft` | `#1AFF6B3D` | `#33FF8A5A` | 选中底色 / Tag 底色 / Soft 按钮（10–20% 透明） |
| `app_brand_dark` | `#D14E20` | `#E07042` | 渐变深色端（替代 `AppColor.BrandDark`） |
| `app_on_brand` | `#FFFFFF` | `#FFFFFF` | 落在 brand 上的文字（替代 `AppColor.OnBrand`） |
| `app_divider` | `#1F000000` | `#1FFFFFFF` | 全局分隔线（替代 `AppColor.Divider`） |
| `app_shadow` | `#1A000000` | `#33000000` | 全局阴影（替代 `AppColor.Shadow`） |

> **`home_*` token 不变**：保留首页改版那 8 个 `home_*` token 不动。`app_brand` 与 `home_accent` 浅色值都是 `#FF6B3D`，深色都是 `#FF8A5A`，但语义独立——`home_*` 是"首页氛围"，`app_brand` 是"全局品牌"，将来可能按场景微调。

### 1.2 Theme.ets 改造

`AppColor` 类的 7 个字面 hex 字段全部改为 `Resource` 句柄，类型从 `string` 变 `Resource`：

```typescript
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

  // 玻璃态 / 描边等没有迁移需求的字段保留 hex（这些只在 MiniPlayer/PlayerPage 半透明遮罩用）
  static readonly GlassBg: string = '#33FFFFFF';
  static readonly GlassBgDark: string = '#33000000';
  static readonly GlassStroke: string = '#1FFFFFFF';
}
```

> **类型变化的影响**：项目里所有 `.backgroundColor(AppColor.Brand)` / `.fontColor(AppColor.Brand)` / `.fontColor([AppColor.Brand])` 等链式调用，因 `Resource` 已经是 `ResourceColor` 子集，**不需要改 callsite**。但 `.backgroundColor(this.x ? AppColor.Brand : '#0D000000')` 这种"三元混合 string/Resource" 的位置编译会报类型不匹配，需要把 `'#0D000000'` 也换成资源（或用 `$r()` 包一下）。
>
> 三元混合 string 的位置预计 ~5 处（PlayerPage / SourcePage / BlockMorePage），逐个查 grep 处理。

### 1.3 BrandSoft 字段已存在于现 AppColor

> 当前 `AppColor` 只有 `Brand / BrandSoft / BrandDark / OnBrand / GlassBg / GlassBgDark / GlassStroke / Shadow / Divider` 共 9 个字段（`BrandSoft` 是项目原有蓝色软底，本次切到 `app_brand_soft` 暖橙软底；语义保持"软强调底色"不变）。

新增 `BrandHover` / `BrandPressed` / `BrandDisabled` 三个字段（按钮系统需要），其它字段类型从 `string` 改为 `Resource`。

---

## 2. AppButton 组件设计

### 2.1 输入

新建 `entry/src/main/ets/components/AppButton.ets`：

```typescript
export enum AppButtonVariant {
  Primary = 0,    // 实心橙底白字 → 主 CTA
  Secondary = 1,  // 软橙底橙字 → 次要操作
  Ghost = 2,      // 透明底橙字 + 边框 → 弱操作
}

export enum AppButtonSize {
  Md = 0,  // 高 40，padding 12+20
  Sm = 1,  // 高 32，padding 8+16
}

@ComponentV2
export struct AppButton {
  @Param label: string = '';
  @Param variant: AppButtonVariant = AppButtonVariant.Primary;
  @Param size: AppButtonSize = AppButtonSize.Md;
  @Param disabled: boolean = false;
  @Param loading: boolean = false;
  @Param fullWidth: boolean = false;
  @Param leadingIcon: Resource | null = null; // 可选 sys.symbol
  @Event onTap: () => void = () => {};
}
```

### 2.2 视觉规格

| variant | 默认背景 | 默认文字 | 按下背景 | 禁用背景 | 边框 |
|---|---|---|---|---|---|
| Primary | `AppColor.Brand` | `AppColor.OnBrand` | `AppColor.BrandPressed` | `AppColor.BrandDisabled` | 无 |
| Secondary | `AppColor.BrandSoft` | `AppColor.Brand` | `AppColor.BrandSoft`（深一档透明） | 透明 + 灰字 | 无 |
| Ghost | `Color.Transparent` | `AppColor.Brand` | `AppColor.BrandSoft` | 透明 + 灰字 | 1vp `AppColor.Brand` |

| size | 高度 | padding | fontSize |
|---|---|---|---|
| Md | 40vp | `{ left: 20, right: 20 }` | 14 |
| Sm | 32vp | `{ left: 16, right: 16 }` | 13 |

圆角统一 `AppRadius.Pill (999)`（药丸状）。Loading 时显示 `LoadingProgress` 替代文字，宽度保持。Disabled 时按钮 `.enabled(false)` 且 `.opacity(1)`（不靠透明度，靠 BrandDisabled 色表达禁用）。

### 2.3 按下态实现

ArkUI 没有 hover/pressed 伪类，用 `Button` 自带的 `.stateEffect(false)` 关掉默认蒙层 + 用 `@Local` 跟踪 `pressed` 状态 + `onTouch(TouchEvent)` 切换背景色。

```typescript
@Local pressed: boolean = false;

Button() { ... }
  .stateEffect(false)
  .onTouch((e) => {
    if (e.type === TouchType.Down) this.pressed = true;
    else if (e.type === TouchType.Up || e.type === TouchType.Cancel) this.pressed = false;
  })
  .backgroundColor(this.computeBg())
```

`computeBg()` 按 disabled / loading / pressed / variant 组合返回 `Resource | string`。

---

## 3. 迁移范围（按文件）

| 文件 | 改动 |
|---|---|
| `theme/Theme.ets` | `AppColor` 9 个字段类型从 string 转 Resource，新增 3 个 hover/pressed/disabled |
| `resources/base/element/color.json` | 追加 9 个 `app_*` token（其中 `app_brand_soft` 为已用蓝色字段的暖橙替代） |
| `resources/dark/element/color.json` | 追加同名 9 个深色值 |
| `components/AppButton.ets` | 新建，3×2 variant/size 矩阵 |
| `components/BookCard.ets` | 1 处 `AppColor.Brand` |
| `components/SourceListItem.ets` | 3 处 `AppColor.Brand` |
| `pages/HomePage.ets` | 0 处（已经全走 HomeTheme.* 与 sys.color.*） |
| `pages/PlayerPage.ets` | 13 处 `AppColor.Brand`，Slider 颜色、segment 选中、章节当前色、睡眠选中——**封面派生 accentColor / blurColor 不动** |
| `pages/SourcePage.ets` | 16 处 `AppColor.Brand` + 三元混合 string 处理 |
| `pages/ImportPage.ets` | 5 处 `AppColor.Brand` + 三元混合 string |
| `pages/FavoritePage.ets` | 2 处 `AppColor.Brand` |
| `pages/BookDetailPage.ets` | 6 处 `AppColor.Brand` + 3 处 `AppColor.Divider` |
| `pages/BlockMorePage.ets` | 2 处 `AppColor.Brand` |
| `pages/AboutPage.ets` | 1 处 `AppColor.BrandDark` + 1 处 `AppColor.Brand`（渐变） |

> **不动**：MiniPlayer（已经全 `sys.color.*`）、HomePage（已切 HomeTheme）、SettingsPage（已经全 `sys.color.*`）、`ColorPickerUtils.*`（封面派生色，与本设计无关）

### 3.1 AppButton 替换原始 Button 的范围

> 本期**只把"主 CTA"改成 AppButton**，其它原始 Button（icon-only、列表内嵌按钮）保持原写法但底层颜色跟着 token 变。
>
> "主 CTA" 是指：
> - SourcePage：导入按钮、保存按钮、确认订阅按钮
> - ImportPage：完成导入按钮、跳转书源按钮
> - PlayerPage：本期不改 Button 形态（只切色）

### 3.2 三元混合 string 处理

grep 出的"三元 hex"位置（用 `Resource` 后必须是同类型）：

| 文件:行 | 原代码 | 改后 |
|---|---|---|
| `PlayerPage.ets:830` | `? AppColor.Brand : '#0D000000'` | `? AppColor.Brand : $r('sys.color.comp_background_tertiary')` |
| `SourcePage.ets:980` | `? AppColor.Brand : Color.Transparent` | `? AppColor.Brand : Color.Transparent`（Color 枚举与 Resource 兼容）|
| `SourcePage.ets:1023` | `? AppColor.Brand : '#CCCCCC'` | `? AppColor.Brand : AppColor.BrandDisabled` |
| `SourcePage.ets:1145` | `? AppColor.Brand : '#CCCCCC'` | `? AppColor.Brand : AppColor.BrandDisabled` |
| `ImportPage.ets:567` | `? AppColor.Brand : '#CCCCCC'` | `? AppColor.Brand : AppColor.BrandDisabled` |

> Color 枚举类型 `Color.Transparent` 与 `Resource` 在 `ResourceColor` 联合下兼容，无需转换。`#0D000000` 这种半透明黑改成 `sys.color.comp_background_tertiary`（系统已自带浅深双值）。

---

## 4. 验收标准

### 功能
- 所有引用 `AppColor.Brand` 的位置在浅色下显示 `#FF6B3D` 暖橙
- 系统切深色，所有引用即时变 `#FF8A5A` 提亮暖橙，无重启
- AppButton 三 variant 按下时背景色立即切到 Pressed 色
- AppButton disabled=true 时颜色变浅且 onClick 不触发
- AppButton loading=true 时文字被 LoadingProgress 替代，按钮整体不可点

### 视觉
- 浅色模式：所有按钮 / Slider / Tab 选中色 / 章节当前色统一为暖橙
- 深色模式：暖橙提亮 10%，对比度达标
- PlayerPage 封面派生色不变（accentColor 来自封面），13 处 AppColor.Brand 改为暖橙后与封面色形成"封面氛围 + 品牌操作"的层次

### 实现边界
- 改动文件：见 §3 表
- 不引入新依赖
- 不动封面取色逻辑（`ColorPickerUtils` / `accentColor` / `blurColor`）
- 不动 MiniPlayer / SettingsPage（已无 Brand 引用）

---

## 5. 文档合规规则

承袭 [首页 spec §9](2026-06-03-homepage-redesign-design.md)：

- 写代码前对非显然 ArkUI API 查 context7 / hmos-arkts-knowledge-retriever
- 禁字面 hex（除 GlassBg/GlassBgDark/GlassStroke 三个保留半透明蒙层不动）
- 禁 V1 装饰器；AppButton 走 `@ComponentV2`
- 每个文件改完跑 `mcp__deveco__check_ets_files`，0 error 0 warning（unused 暂存除外）
- 全部完成后跑一次 `assembleHap` 全量 build

---

## 6. 风险与回退

| 风险 | 验证 | 回退 |
|---|---|---|
| `AppColor` 字段类型从 string 变 Resource，部分调用方编译报错 | 改完 Theme.ets 立即跑全量 check，定位所有报错点 | 报错点逐个改三元 / 类型转换 |
| `Button` 的 `.stateEffect` API 在 6.1.0 是否有变化 | context7 查 ArkUI Button stateEffect 文档 | 用 onTouch + @Local 自实现按下态 |
| 三元混合 string/Resource 编译报错爆炸 | 第一遍编译看报错数 | 如 >20 处，先发一个"仅 Theme 定义"的过渡 commit，分两步走 |
| AppButton Loading 时宽度变化 | UI 看按钮按下"加载中"会不会抖动 | LoadingProgress + 隐藏文字，文字保持 visibility hidden 占位 |
| 封面取色页面的 13 处 AppColor.Brand 改色后视觉冲突 | 真机进 PlayerPage 看章节列表选中色 + 封面色是否打架 | 极端情况这 13 处改回封面派生 accentColor（独立 PR） |

---

## 7. 与首页改版的关系

- 本期不删 `HomeTheme` 类，首页继续走 `HomeTheme.*`，与 `AppColor.*` 是独立两套 token，浅色值相同（`#FF6B3D`）但语义独立
- 未来可以再做一次"语义合并"PR，把 HomeTheme 与 AppColor 合并成单一品牌 token 系统；本期不做
