# 首页重设计 · 设计稿

> 目标：把 [HomePage.ets](entry/src/main/ets/pages/HomePage.ets) 从"搜索框 + 一堆横向板块"的扁平结构，重做为一个有视觉焦点、有续听入口、气质偏 Apple Books 沉浸式的首页。

## 已决策项

| 维度 | 决策 |
|---|---|
| 整体风格 | **A · Apple Books 沉浸**：暖色渐变背景、大字标题、留白、卡片阴影柔和 |
| 板块结构 | **续听型**：标题 → 搜索 → **续听卡** → 横向板块 |
| Hero 区域 | **不要**。续听卡是首屏唯一视觉焦点，不再额外加 Hero |
| 续听卡空态 | **替换为「今日推荐」**：无历史时从首个 HomeBlock 取一本顶上去，卡的形态不变 |

---

## 1. 页面结构（自上而下）

```
┌─────────────────────────┐
│ HdsNavigation 标题区     │  ← 大标题"首页" + GRADIENT_BLUR 滚动效果(已有)
├─────────────────────────┤
│ Search                  │  ← 复用现有 Search 组件
├─────────────────────────┤
│ 🎧 ResumeCard           │  ← 新增。续听 / 今日推荐 二态共用
├─────────────────────────┤
│ 📚 HomeBlock #1          │  ← 复用现有 buildHomeBlock
│ 📚 HomeBlock #2          │
│ ...                     │
├─────────────────────────┤
│ 底部留白(避开浮动 Tab)    │
└─────────────────────────┘
```

**搜索激活后**（`hasSearched=true`）：续听卡 + HomeBlock 整体被搜索结果列表替换，行为与现状一致；续听卡仅在推荐态显示。

---

## 2. 新增组件：ResumeCard

新建 [components/ResumeCard.ets](entry/src/main/ets/components/ResumeCard.ets)，从 HomePage 拆出来，避免 HomePage 进一步膨胀。

### 2.1 输入

```typescript
@ComponentV2
export struct ResumeCard {
  @Param mode: ResumeCardMode = ResumeCardMode.Empty;  // Resume / Suggest / Empty
  @Param book: Book | null = null;
  @Param chapterTitle: string = '';                     // mode=Resume 时显示
  @Param progress: number = 0;                          // 0~1，mode=Resume 时显示进度条
  @Event onTapBody: () => void = () => {};              // 点卡片主体 → 路由到书
  @Event onTapPlay: () => void = () => {};              // 点圆形播放按钮 → 直接播
}

export enum ResumeCardMode {
  Empty = 0,    // 不显示（首板块也未加载到任何书时）
  Resume = 1,   // 续听：有 lastPlayed
  Suggest = 2,  // 今日推荐：无 lastPlayed，但首板块已有书
}
```

### 2.2 视觉规格

> 详见 §4.5（"ResumeCard 视觉规格（深浅适配后）"）。颜色与阴影统一走 `HomeTheme.*` 资源句柄，本节不重复列。布局尺寸：

| 属性 | 值 |
|---|---|
| 外边距 | `margin: { left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Xs }` |
| 内边距 | `padding: AppSpace.Sm` |
| 圆角 | `AppRadius.Lg` (16) |
| 高度 | 内容自适应，约 76vp |
| 封面 | 44×60vp，圆角 6vp |
| 圆形播放按钮 | 32×32vp |
| 进度条（仅 Resume 模式） | 高 3vp，圆角 2vp |

### 2.3 模式差异

| 模式 | 顶部标签 | 副标题 | 播放按钮 | 进度条 |
|---|---|---|---|---|
| Resume | 继续收听 | `chapterTitle`（章节名） | ▶ 直接续播 | 显示 |
| Suggest | 今日推荐 | `${book.author} · ${book.narrator || '来自' + sourceName}` | ▶ 进入详情自动播 | 不显示 |
| Empty | — | — | — | 整张卡 collapse 到 0 高度 |

### 2.4 交互

- 点卡片主体（除播放按钮外）→ 触发 `onTapBody` → 走现有 `EVT_NAVIGATE_TO_BOOK` 路由
- 点圆形播放按钮 → 触发 `onTapPlay`：
  - Resume 模式：路由 + `progressMs` 续播现有章节
  - Suggest 模式：路由进详情页（实际播放由详情页承接，与现状一致）

---

## 3. HomePage 集成

### 3.1 新增 state

```typescript
@Local resumeMode: ResumeCardMode = ResumeCardMode.Empty;
@Local resumeBook: Book | null = null;
@Local resumeChapterTitle: string = '';
@Local resumeProgress: number = 0;
```

### 3.2 状态计算时机

| 触发 | 行为 |
|---|---|
| `aboutToAppear` | 调 `loadResumeState()` |
| `homeBlocks` 首次填充（`loadHomeBlocks` 流式回调里） | 若当前为 Empty 状态，调 `loadResumeState()` 重算（让 Suggest 兜底生效） |
| `playerState.currentBook` 变化（`@Monitor`） | 调 `loadResumeState()`（用户从其他入口播了一本书，回到首页要看到最新续听） |

### 3.3 `loadResumeState()` 决策树

```
1. 读 PreferenceService.getLastPlayed()
   ├─ 有记录 → 从历史 / 收藏 / SearchCache 还原 Book
   │   └─ 还原成功 → mode=Resume, book=...,
   │                  chapterTitle=lastPlayed.chapterTitle ?? '',
   │                  progress = lastPlayed.progressMs / lastPlayed.durationMs
   └─ 无记录 / 还原失败 ↓

2. 取 homeBlocks[0].books[0] 作为今日推荐
   ├─ 有 → mode=Suggest, book=homeBookFromResult(...)
   └─ 无 → mode=Empty
```

> 实现细节：还原 Book 时优先级 `SearchCache.get(bookId)` → `DataService.getBookById(context, bookId)`。任意一个命中即可，不做网络请求。`SearchCache` 走纯内存 / 同步路径，速度快；`DataService.getBookById` 覆盖收藏与历史，需要 `UIAbilityContext`（HomePage 通过 `getUIContext().getHostContext()` 取）。

### 3.4 列表项变更

[HomePage.ets:253-401](entry/src/main/ets/pages/HomePage.ets#L253-L401) 现在的"第 1 项 Search + 工具栏"扩成两段：

```
ListItem { Search + 搜索后工具栏 }     ← 不变
ListItem { ResumeCard }                ← 新增；mode=Empty 时不渲染整个 ListItem
ListItem { 推荐板块 / 搜索结果 / 空态 } ← 不变
```

---

## 4. 视觉系统调整

> 经背景研究确认：项目内 `entry/src/main/resources/base/element/color.json` 与 `entry/src/main/resources/dark/element/color.json` **均已存在**，HarmonyOS 资源限定符按系统 `colorMode` 自动切换，且 `EntryAbility.onConfigurationUpdate` 已与 `WindowUtils.applySystemBarContent` 联动。新加业务色挂这套机制是阻力最小的路径。
>
> 经 context7 检索 `@kit.UIDesignKit` 官方文档：HdsNavigation 自身不需要 dark 开关，深浅切换由 `$r('sys.color.*')` 默认色板 + `MaterialType.ADAPTIVE` 系统 tint 完成；本设计**不显式覆写** `originalStyle / scrollEffectStyle`，沿用默认。

### 4.1 颜色 token 落地路径

新增首页业务色一律走资源限定符（`base` 与 `dark` 两份 element 资源），通过 `theme/Theme.ets` 新增 `HomeTheme` 类以 `Resource` 句柄暴露。**禁止再写 `'#FFF8F3'` 这类字面 hex 在 ArkTS 文件里**，否则深色模式下会变成 bug。

资源新增（追加进现有 `color.json` 的 color 数组，不删旧值）：

| token | base (浅色) | dark (深色) | 用途 |
|---|---|---|---|
| `home_bg_warm_top` | `#FFF3E2` | `#2A1F14` | 页面背景渐变第 0 站，暖意起点 |
| `home_bg_warm_mid` | `#FFF9F1` | `#1F1812` | 渐变 35% 站，过渡到中性 |
| `home_bg_neutral` | `#F5F5F5` | `#1A1A1A` | 渐变末端，与现有 `page_background` 取齐 |
| `home_accent` | `#FF6B3D` | `#FF8A5A` | 暖橙强调色（续听标签 / 播放按钮 / 进度条 fill） |
| `home_accent_soft` | `#1AFF6B3D` | `#33FF8A5A` | 强调色 10–20% 透明，用于按钮按下态、tag 底色 |
| `home_card_surface` | `#FFFFFF` | `#2C2C2C` | ResumeCard 卡片底色（与 `card_background` 同值，独立 token 便于以后微调） |
| `home_card_shadow` | `#14000000` | `#33000000` | ResumeCard 投影色，深色加重避免阴影"消失" |
| `home_progress_track` | `#0F000000` | `#1FFFFFFF` | 进度条 track（仅 ResumeCard 用） |

> **深色 home_accent 取 `#FF8A5A`**：原 `#FF6B3D` 在深色暖背景上对比度勉强达标，提亮 10% 视觉重量更稳。这是 review 给错（强调色给成品牌蓝 `#0A59F7`）后的人工纠正。

### 4.2 Theme.ets 修改

```typescript
// theme/Theme.ets，AppColor 类保持不变（不改全局品牌色），追加：

export class HomeTheme {
  static readonly BgWarmTop = $r('app.color.home_bg_warm_top');
  static readonly BgWarmMid = $r('app.color.home_bg_warm_mid');
  static readonly BgNeutral = $r('app.color.home_bg_neutral');
  static readonly Accent = $r('app.color.home_accent');
  static readonly AccentSoft = $r('app.color.home_accent_soft');
  static readonly CardSurface = $r('app.color.home_card_surface');
  static readonly CardShadow = $r('app.color.home_card_shadow');
  static readonly ProgressTrack = $r('app.color.home_progress_track');
}
```

> **不改 `AppColor.Brand` / `AppColor.Divider` / `AppColor.Shadow`**：项目内 9 个文件（PlayerPage / SourcePage / BookDetailPage / ImportPage / FavoritePage / BlockMorePage / SourceListItem / BookCard / AboutPage）共 40+ 处直接引用 `AppColor.Brand`，本次首页改版不连坐这些页面的颜色迁移。AppColor 字段的全局深浅化排到独立迭代。

### 4.3 沉浸保持机制：暖色背景挂在哪

**当前 HomePage 没有页面级背景**——背景靠 HdsNavigation 默认色板（`$r('sys.color.*')`）。直接给 `List` 加 `linearGradient` 会随滚动消失，给 `titleBar.style.originalStyle.backgroundStyle` 又会和 `MaterialType.ADAPTIVE` 的系统 tint 叠加产生颜色脏污。

**方案**：在 `build()` 顶层用 `Stack` 包一层全屏渐变背景，HdsNavigation 在其上层。

```typescript
build() {
  Stack({ alignContent: Alignment.TopStart }) {
    // L0 背景渐变层（满屏，含状态栏区域）
    Column()
      .width('100%')
      .height('100%')
      .linearGradient({
        angle: 180,
        colors: [
          [HomeTheme.BgWarmTop, 0.0],
          [HomeTheme.BgWarmMid, 0.35],
          [HomeTheme.BgNeutral, 1.0]
        ]
      })

    // L1 HdsNavigation（保持现有配置不动）
    HdsNavigation() {
      Refresh(...) {
        List(...) { /* ListItem × N，透明背景，让 L0 透出 */ }
          .clip(false)        // 保留：穿透到标题栏产生光感
          .backgroundColor(Color.Transparent)  // 新增：让 L0 暖色透出
      }
    }
    .titleBar({ /* GRADIENT_BLUR + ADAPTIVE 维持现状 */ })
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .bindToScrollable([this.contentScroller])
  }
  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
}
```

**关键约束**（每条都有理由，违反就破坏沉浸）：

- `Stack` 必须 `alignContent: TopStart`，否则 HdsNavigation 默认居中会扰乱 titleBar 安全区计算
- 渐变 `Column` 必须 `width('100%').height('100%')`，否则 `expandSafeArea` 不会把渐变铺到状态栏区域，顶部出现白边
- 父 Stack 必须 `expandSafeArea([SYSTEM],[TOP])`；HdsNavigation 自带 `enableComponentSafeArea: true` 处理内容区避让，**两者不冲突**——前者管渐变穿透到状态栏，后者管标题文字避让安全区
- `List` 必须 `backgroundColor(Color.Transparent)`，否则覆盖暖色（HomePage 当前没显式设 List 背景，但加这一行作为防御）
- HdsNavigation **不**额外加 `.backgroundColor()`，让 ADAPTIVE 材质从下层透出 tint
- HdsNavigation **不**显式覆写 `originalStyle.backgroundStyle`，否则会和材质 tint 叠加污色
- `cachedCount(5)` 与 `clip(false)` 维持现状

### 4.4 标题区文案

`title.mainTitle` 改为字符串字面量 `'首页'`（context7 已确认 `mainTitle: ResourceStr` 接受 `string | Resource`）。`titleMode` 维持 `MINI` 不变。

副标题 "已启用 X 个书源"：经 context7 验证 `subTitle: ResourceStr` 字段确实存在且 `MINI` 模式支持。但项目内**无任何页面在用**，缺乏参考样本，本期为降低风险**不挂在 `HdsNavigation.subTitle`**，仍按原方案放第一个 `ListItem` 内、Search 上方一行小字。`subTitle` 字段验证留作后续优化。

### 4.5 ResumeCard 视觉规格（深浅适配后）

| 属性 | 浅色 / 深色统一表达 |
|---|---|
| 背景 | `.backgroundColor(HomeTheme.CardSurface)` |
| 圆角 | `AppRadius.Lg` (16) |
| 阴影 | `.shadow({ radius: 14, color: HomeTheme.CardShadow, offsetY: 4 })` |
| 外边距 | `{ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Xs }` |
| 内边距 | `AppSpace.Sm` |
| 封面 | 44×60vp，圆角 6vp，独立 drop-shadow（同 CardShadow） |
| 圆形播放按钮 | 32×32vp，`.backgroundColor(HomeTheme.Accent)`，前景白 `▶` |
| 进度条 (Resume 模式) | 高 3vp，圆角 2vp，track `HomeTheme.ProgressTrack`，fill `HomeTheme.Accent` |
| 标签文字 | `AppFont.Caption (12)`，`.fontColor(HomeTheme.Accent)`，字重 700，letterSpacing 1 |
| 主标题 | `AppFont.BodyL (16)`，`.fontColor($r('sys.color.font_primary'))`，字重 700 |
| 副标题（章节名 / 作者） | `AppFont.Caption`，`.fontColor($r('sys.color.font_tertiary'))` |

---

## 5. 数据流

```
┌─────────────────┐    getLastPlayed()    ┌──────────────────┐
│PreferenceService│──────────────────────▶│  loadResumeState │
└─────────────────┘                       │   (HomePage)     │
                                          │                  │
┌─────────────────┐    streamAllHome…()   │                  │
│BookSourceService│──────────────────────▶│                  │
└─────────────────┘                       │                  │
                                          │                  │
┌─────────────────┐    fallback 还原 Book │                  │
│ DataService /   │──────────────────────▶│                  │
│ SearchCache     │                       └────────┬─────────┘
└─────────────────┘                                │
                                                   ▼
                                          ┌──────────────────┐
                                          │   ResumeCard     │
                                          │  (Resume/Suggest)│
                                          └──────────────────┘
```

播放路由仍走现有 `EVT_NAVIGATE_TO_BOOK`，本设计**不改动**路由 / 播放层。

---

## 6. 不在范围内（明确不做）

- **AppColor 全局深浅化迁移**：本轮只为首页改版新增 `HomeTheme` token；`AppColor.Brand / Divider / Shadow` 在 9 个文件 40+ 处的现有引用保持不动。统一切到 `$r('app.color.*')` 排到独立 PR，避免本次改版 review 体量爆炸。
- **`mediaQuery` 运行时方案**：明确不引入。资源限定符 + `EntryAbility.onConfigurationUpdate` 已经在跑，引入 `matchMediaSync('(dark-mode: dark)')` 只会增加重渲染开销，且对 ArkUI V2 `@Local` 不友好。
- **`WithTheme({colorMode: DARK/LIGHT})` 包裹**：除非未来某页要锁定与系统相反的颜色，本期不用。
- **HdsNavigation `originalStyle / scrollEffectStyle` 自定义**：不写。一旦自定义就要同时维护两份且会和 `systemMaterialEffect` 的 tint 冲突。
- **`HdsNavigation.subTitle` 字段**：经 context7 确认存在且 `MINI` 支持，但项目内零样本，本期改用 `ListItem` 内自绘小字，规避未知风险。
- **`ScrollEffectType` 切换为 `IMMERSIVE_GRADIENT_BLUR`**：不做。该枚举官方面向"沉浸式图文"，HomePage 是"非沉浸式列表场景"，错位会导致顶部模糊过深。
- **暖色随专辑封面动态化**：第二阶段需求，本轮 `HomeTheme.BgWarmTop` 是静态 token，不接 `ColorPickerUtils`。
- **不改搜索态 UI / BookCard / `buildHomeBlock` 视觉**：仅推荐态新增 ResumeCard，搜索态完全维持现状。
- **不动 `WindowUtils.applySystemBarContent`**：状态栏字色已按 colorMode 自适应。

---

## 7. 验收标准

### 功能
- 有续听记录时：首屏第一眼看到"继续收听"卡，封面 + 章节名 + 进度条，点 ▶ 直接续播
- 无续听记录但有书源板块时：首屏第一眼看到"今日推荐"卡（来自首板块第一本）
- 无续听 + 无书源板块时：续听卡区域完全不占空间（`mode = Empty`，整个 ListItem 不渲染）
- 用户从其他入口（书架 / 历史）播了一本书后回到首页，续听卡能即时反映最新

### 视觉 & 沉浸
- **浅色模式**：顶部暖色雾化感，标题"首页"清晰，下滑后 GRADIENT_BLUR 模糊过渡平滑，无白边、无颜色断层
- **深色模式**：顶部低饱和暖棕色雾化感，标题对比度达标，ResumeCard 阴影可见，无"暖色被材质完全压住变纯黑"
- **切换实时性**：系统从浅切深的瞬间，首页所有颜色自动跟随（资源限定符行为），无需重启
- 滚动到顶部时大字标题"首页"完整显示，下滑后系统自动应用 GRADIENT_BLUR
- 暖色渐变与现有横向板块卡片不冲突，板块标题在两种 mode 下均可读

### 实现边界
- 改动只触及：[HomePage.ets](entry/src/main/ets/pages/HomePage.ets)、[Theme.ets](entry/src/main/ets/theme/Theme.ets)、`base/element/color.json`、`dark/element/color.json`
- 新增：[components/ResumeCard.ets](entry/src/main/ets/components/ResumeCard.ets)
- 不引入新依赖、不改 oh-package.json

---

## 8. 实现风险与回退预案

| 风险 | 触发条件 | 验证方式 | 回退方案 |
|---|---|---|---|
| **静态字段 `$r()` 求值时机** | `HomeTheme` 类静态字段在 Theme.ets 被 import 时若资源系统未就绪可能拿到非法 Resource | HomePage `aboutToAppear` 中 `console.log(HomeTheme.BgWarmTop)`，看是否拿到合法 Resource 对象（含 `bundleName / moduleName / id`） | 改成 getter：`static get BgWarmTop() { return $r('app.color.home_bg_warm_top'); }` |
| **`expandSafeArea` 双重避让** | 父 Stack `expandSafeArea([SYSTEM],[TOP])` + HdsNavigation `enableComponentSafeArea: true` 是否会双倍避让 | 真机看搜索框上沿到状态栏底部留白是 1× 还是 2× 状态栏高度 | 双重则把 `enableComponentSafeArea` 改 `false`，由父 Stack 统一负责 |
| **暖色被 ADAPTIVE 材质压住** | 深色下 `home_bg_warm_top = #2A1F14` 与系统暗色磨砂叠加可能损失暖意 | 深色 A/B：A 用 `#2A1F14`，B 用 `#3D2A18` | 调高深色版饱和度，最坏改成 `#3D2A18` |
| **GRADIENT_BLUR 性能** | 低端设备 `MaterialLevel.ADAPTIVE` 会降级到 `SMOOTH`，叠加 List 滚动 + 暖色渐变可能掉帧 | 在最低支持机型跑 systrace 看 fps | 提供 `PreferenceService` 选项把 `GRADIENT_BLUR` 临时降为 `COMMON_BLUR` |
| **ResumeCard `mode=Empty` 状态闪烁** | 异步加载首板块期间 `homeBlocks[0]` 由 undefined 变 [book]，ResumeCard 从 Empty 跳到 Suggest 视觉跳动 | 冷启动看首屏渲染时序 | `loadResumeState` 在 `homeBlocks` 真正 push 第一本之前不切换到 Suggest（已在 §3.2 决策树覆盖） |

---

## 9. ArkUI / HarmonyOS 文档合规规则（开发硬约束）

> 本节是写代码时的强制规则，违反任意一条都不算实施完成。

### 9.1 必须查文档的 API

写每一个新增 / 修改代码前，**先查官方文档确认 API 形态**，不得凭经验或类比 RN/Vue/iOS 写法落地。需要明确查文档的 API 至少包括：

| API | 文档源 |
|---|---|
| `HdsNavigation` titleBar 各字段、ScrollEffectType 枚举值 | `mcp__context7__dispatch query-docs` 取 `/huaweideveloper/ui-design-hdsnavigation` |
| `hdsMaterial.MaterialType` / `MaterialLevel` 枚举可用值与版本 | 同上 |
| `linearGradient` 参数（angle / colors 元组结构） | `mcp__context7__dispatch` 或 `hmos-arkts-knowledge-retriever` |
| `Stack` `alignContent` 枚举、`expandSafeArea` 参数组合 | 同上 |
| `Refresh` 容器组件 onRefreshing / onStateChange 回调签名 | 同上 |
| `Resource` / `$r()` 在 ArkTS V2 静态字段中的求值时机 | `hmos-arkts-knowledge-retriever` |
| `LazyForEach` 在 ResumeCard 嵌入 ListItem 后的 keyGenerator 约束 | 同上 |
| `@ComponentV2` / `@Local` / `@Param` / `@Event` / `@Monitor` 在子组件中的限制 | `hmos-arkts-knowledge-retriever` |

### 9.2 禁止行为

- **不写 `@State` / `@Prop` / `@Link` / `@ObjectLink`**（V1 装饰器，与项目 V2 体系冲突，违反 CLAUDE.md "不混用 V1/V2"）
- **不在颜色相关代码里写字面 hex**（如 `#FFF3E2`），全部走 `HomeTheme.*` 或 `$r('sys.color.*')`
- **不用 `index` 作为 `LazyForEach` / `ForEach` 的 key**（违反 CLAUDE.md "禁止 index 作为 key"）
- **不在 V2 的 TextInput 上写"单向 `text` + `onChange`"**（违反 CLAUDE.md，IME 光标会跳）
- **不引入 npm / ohpm 新依赖**

### 9.3 实施时的"先查再写"流程

每个改动按下面顺序：
1. 起草要写的 ArkUI 代码片段
2. 列出片段中所有 API（含装饰器、组件、链式属性）
3. 对每个非显然的 API 调用一次 `mcp__context7__dispatch query-docs` 或 `hmos-arkts-knowledge-retriever`，把"文档原话 / 关键示例"写进 PR 描述
4. 如果文档与代码不一致 → 改代码，不改文档解读
5. 写完后用 `hmos-arkts-syntax-checker` 跑一遍编译，零错误零警告才算完成
6. 如果编译报错涉及废弃 API，用 `hmos-arkts-deprecated-interface-checker` 检索替代方案

### 9.4 文档证据归档

实施期间获取的文档摘录（API 签名、示例代码、版本注记）以"引用 + 链接"形式记录在 PR 描述里，便于 reviewer 不重复查文档。本 spec 已记录的关键文档证据：
- `HdsNavigationTitle.mainTitle: ResourceStr (required)` / `subTitle: ResourceStr (optional)` ——`ui-design-hdsnavigation` 文档，起始版本 5.1.0(18)
- `ScrollEffectType.GRADIENT_BLUR(2)` 起始版本 6.0.0(20)、`IMMERSIVE_GRADIENT_BLUR(3)` 起始版本 6.1.0(23)
- `systemMaterialEffect` 字段起始版本 6.1.0(23)，`MaterialType.ADAPTIVE` "defaults to immersive"
- `MaterialLevel.ADAPTIVE` 在 EXQUISITE / GENTLE / SMOOTH 三档中由系统动态选择
