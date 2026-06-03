# 全局色板迁移 + AppButton 系统 实施计划

> **For agentic workers:** 用 subagent-driven-development 或 executing-plans 逐 Task 实施。每个步骤都是 checkbox。

**Goal:** 把 `AppColor.Brand` 蓝色从 9 个文件 50+ 处替换为暖橙 `#FF6B3D`，全局深浅模式适配，新增 `AppButton` 组件统一 CTA 按钮的状态系统。

**Architecture:**
- 9 个新 `app_*` 资源 token 走 `base/element/color.json` + `dark/element/color.json` 双份
- `AppColor` 类的 7 个 brand 字段类型从 `string` 改为 `Resource`，保留 `GlassBg/GlassBgDark/GlassStroke` 字面 hex（半透明蒙层）
- 新建 `AppButton` 组件（V2，3 variant × 4 state）
- PlayerPage 封面派生色（accentColor / blurColor / ColorPickerUtils）完全不动

**Spec 来源：** [2026-06-03-global-palette-migration-design.md](docs/superpowers/specs/2026-06-03-global-palette-migration-design.md)

---

## 文件清单

| 文件 | 操作 |
|---|---|
| `entry/src/main/resources/base/element/color.json` | 追加 9 个 `app_*` token |
| `entry/src/main/resources/dark/element/color.json` | 追加同名 9 个 |
| `entry/src/main/ets/theme/Theme.ets` | `AppColor` 字段 string → Resource，新增 BrandHover/BrandPressed/BrandDisabled |
| `entry/src/main/ets/components/AppButton.ets` | 新建 |
| `entry/src/main/ets/components/BookCard.ets` | 1 处 |
| `entry/src/main/ets/components/SourceListItem.ets` | 3 处 |
| `entry/src/main/ets/pages/PlayerPage.ets` | 13 处 + 三元 mix 1 处 |
| `entry/src/main/ets/pages/SourcePage.ets` | 16 处 + 三元 mix 3 处 |
| `entry/src/main/ets/pages/ImportPage.ets` | 5 处 + 三元 mix 1 处 |
| `entry/src/main/ets/pages/FavoritePage.ets` | 2 处 |
| `entry/src/main/ets/pages/BookDetailPage.ets` | 6 处 + 3 处 Divider |
| `entry/src/main/ets/pages/BlockMorePage.ets` | 2 处 |
| `entry/src/main/ets/pages/AboutPage.ets` | 1 处 BrandDark + 1 处 Brand |

---

## 文档合规规则

承袭首页 plan §9：每个 ArkUI 改动前查文档；编译用 `mcp__deveco__check_ets_files`；禁字面 hex（GlassBg 三个例外）；禁 V1 装饰器。

---

## Task 1: 注册 9 个 `app_*` token（浅/深双份）

**Files:**
- Modify: `entry/src/main/resources/base/element/color.json`
- Modify: `entry/src/main/resources/dark/element/color.json`

- [ ] **Step 1.1: base 追加 9 个 token**

把 `entry/src/main/resources/base/element/color.json` 的 color 数组末尾追加：

```json
    { "name": "app_brand", "value": "#FF6B3D" },
    { "name": "app_brand_hover", "value": "#FF8559" },
    { "name": "app_brand_pressed", "value": "#E55520" },
    { "name": "app_brand_disabled", "value": "#FFD0BC" },
    { "name": "app_brand_soft", "value": "#1AFF6B3D" },
    { "name": "app_brand_dark", "value": "#D14E20" },
    { "name": "app_on_brand", "value": "#FFFFFF" },
    { "name": "app_divider", "value": "#1F000000" },
    { "name": "app_shadow", "value": "#1A000000" }
```

- [ ] **Step 1.2: dark 追加同名 9 个深色值**

```json
    { "name": "app_brand", "value": "#FF8A5A" },
    { "name": "app_brand_hover", "value": "#FFA078" },
    { "name": "app_brand_pressed", "value": "#E0764A" },
    { "name": "app_brand_disabled", "value": "#5C3F2F" },
    { "name": "app_brand_soft", "value": "#33FF8A5A" },
    { "name": "app_brand_dark", "value": "#E07042" },
    { "name": "app_on_brand", "value": "#FFFFFF" },
    { "name": "app_divider", "value": "#1FFFFFFF" },
    { "name": "app_shadow", "value": "#33000000" }
```

- [ ] **Step 1.3: 验证 JSON + 同步**

```bash
node -e "
const base = JSON.parse(require('fs').readFileSync('entry/src/main/resources/base/element/color.json'));
const dark = JSON.parse(require('fs').readFileSync('entry/src/main/resources/dark/element/color.json'));
const baseApp = base.color.filter(c => c.name.startsWith('app_')).map(c => c.name).sort();
const darkApp = dark.color.filter(c => c.name.startsWith('app_')).map(c => c.name).sort();
console.log('base app_* tokens:', baseApp.length);
console.log('match:', JSON.stringify(baseApp) === JSON.stringify(darkApp));
"
```
Expected: `base app_* tokens: 9`，`match: true`

- [ ] **Step 1.4: Commit**

```bash
git add entry/src/main/resources/base/element/color.json entry/src/main/resources/dark/element/color.json
git commit -m "feat(theme): 新增 app_* 全局品牌色 token (浅/深双份)

9 个 token 准备替代 AppColor 字面 hex:
- app_brand/hover/pressed/disabled/soft/dark
- app_on_brand
- app_divider/shadow"
```

---

## Task 2: AppColor 类 string → Resource

**Files:**
- Modify: `entry/src/main/ets/theme/Theme.ets`

- [ ] **Step 2.1: 替换 AppColor 类**

把 `entry/src/main/ets/theme/Theme.ets` 中的 `AppColor` 类整段替换为：

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

  // 半透明蒙层保留字面 hex（玻璃态、覆盖层），不深浅适配
  static readonly GlassBg: string = '#33FFFFFF';
  static readonly GlassBgDark: string = '#33000000';
  static readonly GlassStroke: string = '#1FFFFFFF';
}
```

- [ ] **Step 2.2: 编译检查**

`mcp__deveco__check_ets_files` 目标：`entry/src/main/ets/theme/Theme.ets`
Expected: 0 error 0 warning

- [ ] **Step 2.3: 全量编译看下游报错**

`mcp__deveco__check_ets_files` 目标：所有 9 个文件
```
["entry/src/main/ets/components/BookCard.ets",
 "entry/src/main/ets/components/SourceListItem.ets",
 "entry/src/main/ets/pages/PlayerPage.ets",
 "entry/src/main/ets/pages/SourcePage.ets",
 "entry/src/main/ets/pages/ImportPage.ets",
 "entry/src/main/ets/pages/FavoritePage.ets",
 "entry/src/main/ets/pages/BookDetailPage.ets",
 "entry/src/main/ets/pages/BlockMorePage.ets",
 "entry/src/main/ets/pages/AboutPage.ets"]
```

预期：`AppColor.Brand : '#xxxxxx'` 三元混合的位置会报"Type 'string' is not assignable to type 'Resource | Color'"。

把所有报错点列出来，下个 Task 集中改三元混合。

- [ ] **Step 2.4: 不 commit**，等三元修完一起。

---

## Task 3: 修三元混合 string

**Files:**
- Modify: `entry/src/main/ets/pages/PlayerPage.ets`
- Modify: `entry/src/main/ets/pages/SourcePage.ets`
- Modify: `entry/src/main/ets/pages/ImportPage.ets`

- [ ] **Step 3.1: PlayerPage.ets:830**

定位：
```typescript
.backgroundColor(this.chapterSegmentIndex === segIdx ? AppColor.Brand : '#0D000000')
```

改为：
```typescript
.backgroundColor(this.chapterSegmentIndex === segIdx ? AppColor.Brand : $r('sys.color.comp_background_tertiary'))
```

- [ ] **Step 3.2: SourcePage.ets:1023 + :1145**

两处都是：
```typescript
.backgroundColor(this.xxx ? AppColor.Brand : '#CCCCCC')
```

改为：
```typescript
.backgroundColor(this.xxx ? AppColor.Brand : AppColor.BrandDisabled)
```

> 注：先用 grep 拿到精确行号 `grep -n "AppColor.Brand : '#" entry/src/main/ets/pages/SourcePage.ets`

- [ ] **Step 3.3: ImportPage.ets:567**

```typescript
.backgroundColor(this.canImport() ? AppColor.Brand : '#CCCCCC')
```

改为：
```typescript
.backgroundColor(this.canImport() ? AppColor.Brand : AppColor.BrandDisabled)
```

- [ ] **Step 3.4: 编译验证**

`mcp__deveco__check_ets_files` 三个文件，预期都 0 error。

- [ ] **Step 3.5: Commit Task 2 + 3**

```bash
git add entry/src/main/ets/theme/Theme.ets entry/src/main/ets/pages/PlayerPage.ets entry/src/main/ets/pages/SourcePage.ets entry/src/main/ets/pages/ImportPage.ets
git commit -m "feat(theme): AppColor 字段 string→Resource, 修三元混合

- AppColor.Brand 等 7 个字段改为 \$r('app.color.app_*')
- 新增 BrandHover/BrandPressed/BrandDisabled
- GlassBg/GlassBgDark/GlassStroke 保持字面 hex (半透明蒙层)
- 修 5 处三元混合 string: '#0D000000'→sys 资源, '#CCCCCC'→BrandDisabled

下游 9 文件 50+ 处 AppColor.Brand 引用因 Resource 与 ResourceColor
联合类型兼容, 视觉自动切换为暖橙, 无需改 callsite."
```

---

## Task 4: 新建 AppButton 组件

**Files:**
- Create: `entry/src/main/ets/components/AppButton.ets`

- [ ] **Step 4.1: 查文档**

用 `mcp__context7__query-docs` 查 ArkUI Button stateEffect、TouchEvent、LoadingProgress 样式规格。

要点：
- `Button.stateEffect(false)` 关闭默认蒙层
- `onTouch((e: TouchEvent) => ...)` 接 `TouchType.Down/Up/Cancel`

- [ ] **Step 4.2: 写 AppButton**

```typescript
import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';

export enum AppButtonVariant {
  Primary = 0,
  Secondary = 1,
  Ghost = 2,
}

export enum AppButtonSize {
  Md = 0,
  Sm = 1,
}

@ComponentV2
export struct AppButton {
  @Param label: string = '';
  @Param variant: AppButtonVariant = AppButtonVariant.Primary;
  @Param size: AppButtonSize = AppButtonSize.Md;
  @Param disabled: boolean = false;
  @Param loading: boolean = false;
  @Param fullWidth: boolean = false;
  @Param leadingIcon: Resource | null = null;
  @Event onTap: () => void = () => {};

  @Local pressed: boolean = false;

  build() {
    Button() {
      Stack() {
        // Loading 时显示进度条覆盖文字
        if (this.loading) {
          LoadingProgress()
            .width(this.size === AppButtonSize.Md ? 18 : 14)
            .height(this.size === AppButtonSize.Md ? 18 : 14)
            .color(this.fgColor())
        } else {
          Row({ space: AppSpace.Xs }) {
            if (this.leadingIcon) {
              SymbolGlyph(this.leadingIcon)
                .fontSize(this.size === AppButtonSize.Md ? 16 : 14)
                .fontColor([this.fgColor()])
            }
            Text(this.label)
              .fontSize(this.size === AppButtonSize.Md ? AppFont.Body : 13)
              .fontColor(this.fgColor())
              .fontWeight(FontWeight.Bold)
          }
          .alignItems(VerticalAlign.Center)
        }
      }
    }
    .width(this.fullWidth ? '100%' : undefined)
    .height(this.size === AppButtonSize.Md ? 40 : 32)
    .padding({
      left: this.size === AppButtonSize.Md ? 20 : 16,
      right: this.size === AppButtonSize.Md ? 20 : 16
    })
    .backgroundColor(this.bgColor())
    .borderRadius(AppRadius.Pill)
    .borderWidth(this.variant === AppButtonVariant.Ghost ? 1 : 0)
    .borderColor(this.variant === AppButtonVariant.Ghost ? AppColor.Brand : Color.Transparent)
    .stateEffect(false)
    .enabled(!this.disabled && !this.loading)
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) this.pressed = true;
      else if (e.type === TouchType.Up || e.type === TouchType.Cancel) this.pressed = false;
    })
    .onClick(() => {
      if (this.disabled || this.loading) return;
      this.onTap();
    })
  }

  private bgColor(): ResourceColor {
    if (this.disabled) {
      if (this.variant === AppButtonVariant.Primary) return AppColor.BrandDisabled;
      return Color.Transparent;
    }
    if (this.variant === AppButtonVariant.Primary) {
      return this.pressed ? AppColor.BrandPressed : AppColor.Brand;
    }
    if (this.variant === AppButtonVariant.Secondary) {
      return AppColor.BrandSoft;
    }
    // Ghost
    return this.pressed ? AppColor.BrandSoft : Color.Transparent;
  }

  private fgColor(): ResourceColor {
    if (this.disabled) {
      if (this.variant === AppButtonVariant.Primary) return AppColor.OnBrand;
      return $r('sys.color.font_tertiary');
    }
    if (this.variant === AppButtonVariant.Primary) return AppColor.OnBrand;
    return AppColor.Brand;
  }
}
```

- [ ] **Step 4.3: 编译**

`mcp__deveco__check_ets_files` 目标：`entry/src/main/ets/components/AppButton.ets`
Expected: 0 error 0 warning

- [ ] **Step 4.4: Commit**

```bash
git add entry/src/main/ets/components/AppButton.ets
git commit -m "feat: 新建 AppButton 组件 (3 variant × 4 state)

- Primary/Secondary/Ghost 三种 variant
- Default/Pressed/Disabled/Loading 四种 state
- Md/Sm 两档尺寸
- 走 AppColor.Brand/Pressed/Disabled/Soft/OnBrand token
- onTouch + @Local pressed 实现按下态切色"
```

---

## Task 5: 直接迁移 — 因 Resource 与 string 在 ResourceColor 联合类型下兼容，**所有 `AppColor.Brand` callsite 不需要改代码**，颜色自动切换为暖橙

> Task 2 + 3 完成后，下游 50+ 处 `AppColor.Brand` 已经全部走资源限定符暖橙。本 Task 仅做编译验证 + 视觉确认。

**Files:** 无代码改动

- [ ] **Step 5.1: 全量编译**

`mcp__deveco__build_project` debug mode
Expected: BUILD SUCCESSFUL

- [ ] **Step 5.2: 列改动 stat**

```bash
git diff main --stat -- entry/src/main/ets entry/src/main/resources
```
Expected: 只有
- `theme/Theme.ets`
- `components/AppButton.ets`（新建）
- `pages/PlayerPage.ets` / `SourcePage.ets` / `ImportPage.ets`（仅三元修复）
- 两份 `color.json`

> 不应该有 BookCard / SourceListItem / FavoritePage / BookDetailPage / BlockMorePage / AboutPage 的改动——它们的 `AppColor.Brand` 引用是直接传入，类型兼容自动迁移。

---

## Task 6: AppButton 接入 SourcePage / ImportPage 主 CTA

> 本期 spec §3.1 限定的 AppButton 替换范围：SourcePage 的导入/保存/订阅按钮，ImportPage 的完成导入/跳转按钮。

**Files:**
- Modify: `entry/src/main/ets/pages/SourcePage.ets`
- Modify: `entry/src/main/ets/pages/ImportPage.ets`

- [ ] **Step 6.1: 看现有 Button 写法找到 CTA 位置**

```bash
grep -nE "Button\(.*\)|backgroundColor\(.*Brand" entry/src/main/ets/pages/SourcePage.ets | head -30
grep -nE "Button\(.*\)|backgroundColor\(.*Brand" entry/src/main/ets/pages/ImportPage.ets | head -20
```

逐个判断哪些是"主 CTA"（按下后会触发跨页或重要写入操作），把它们换成 `AppButton`。

> 这一步因为 Button 写法在每个页面里散布，不强求一次替换完。如果某个 Button 替换后视觉变化太大，可以保留原写法（颜色已经跟着 Task 2 切了）。本 Task 是"机会迁移"，不是硬替换。

- [ ] **Step 6.2: 不 commit**，等 Task 7 一起。

---

## Task 7: 视觉验证

**Files:** 无代码改动

- [ ] **Step 7.1: 全量 build**

`mcp__deveco__build_project` debug mode
Expected: BUILD SUCCESSFUL

- [ ] **Step 7.2: 安装 + 启动 App**

`mcp__deveco__start_app` 任意可用设备

- [ ] **Step 7.3: 浅色模式逐页核验**

| 页面 | 期望 |
|---|---|
| HomePage | 已是暖橙（首页改版已完成）|
| FavoritePage | 收藏卡片选中 / 删除按钮 → 暖橙 |
| SourcePage | Tab ���中 / 导入按钮 → 暖橙 |
| ImportPage | 完成按钮 / 选中态 → 暖橙 |
| PlayerPage | Slider 颜色 / 章节当前 / 睡眠选中 → 暖橙；封面派生背景色不变 |
| BookDetailPage | 收藏按钮 / 播放按钮 → 暖橙；分隔线深色下可见 |
| BlockMorePage | LoadingProgress / 加载文字 → 暖橙 |
| AboutPage | 渐变背景 → 暖橙双段 |
| BookCard 角标 | 推荐角标 → 暖橙 |

- [ ] **Step 7.4: 深色模式核验**

切深色，所有暖橙提亮（`#FF8A5A`），分隔线 `#1FFFFFFF` 在深底可见。

- [ ] **Step 7.5: AppButton 状态核验**

哪个页面接入了 AppButton 就核验对应 Pressed/Disabled/Loading 三态视觉。

- [ ] **Step 7.6: Commit Task 6 + 7（如果 6 有改动）**

如果 Task 6 做了替换：
```bash
git add entry/src/main/ets/pages/SourcePage.ets entry/src/main/ets/pages/ImportPage.ets
git commit -m "refactor: SourcePage/ImportPage 主 CTA 接入 AppButton"
```

如果 Task 6 没改动，跳过此 Step。

---

## 自检清单

- [x] Task 1 → spec §1.1 颜色 token 落地
- [x] Task 2 → spec §1.2 Theme.ets 改造
- [x] Task 3 → spec §3.2 三元混合 string 处理
- [x] Task 4 → spec §2 AppButton 组件
- [x] Task 5 → 验证 spec §3 迁移范围（callsite 自动迁移）
- [x] Task 6 → spec §3.1 AppButton 接入主 CTA
- [x] Task 7 → spec §4 验收
- [x] 每个 ArkUI 改动有"先查文档"的明确入口（Task 4 step 1）
- [x] 每个文件改完编译检查
- [x] PlayerPage 封面派生色 (accentColor/blurColor/ColorPickerUtils) **完全没碰**
- [x] HomePage / MiniPlayer / SettingsPage 不在文件清单（已无 Brand 引用 / 已用 sys.color）
