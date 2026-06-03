# 首页重设计 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 [HomePage.ets](entry/src/main/ets/pages/HomePage.ets) 重做为 Apple Books 风格的暖色沉浸首页：续听卡 → 横向板块。新增 ResumeCard 组件 + HomeTheme 资源 token，**深浅模式自动适配**，**沉浸标题栏不破坏**。

**Architecture:**
- 颜色走 HarmonyOS 资源限定符（`base/element/color.json` + `dark/element/color.json`），通过 `theme/Theme.ets` 内 `HomeTheme` 类用 `$r('app.color.*')` 句柄暴露
- ArkUI V2（`@ComponentV2`/`@Local`/`@Param`/`@Event`/`@Monitor`），不混 V1
- 暖色 `linearGradient` 挂在 `build()` 顶层 `Stack` 上，HdsNavigation 在其上层；`titleBar` 配置完全不动
- 数据：`PreferenceService.getLastPlayed()` → `SearchCache.get` → `DataService.getBookById` 三段还原 Book，无网络

**Tech Stack:** HarmonyOS Next 6.1.0(23)、ArkTS V2、@kit.UIDesignKit (HdsNavigation/hdsMaterial)、@kit.ArkUI (linearGradient/expandSafeArea)、@kit.ArkData (preferences)

**Spec 来源：** [docs/superpowers/specs/2026-06-03-homepage-redesign-design.md](docs/superpowers/specs/2026-06-03-homepage-redesign-design.md)

---

## 文件结构

| 文件 | 操作 | 责任 |
|---|---|---|
| `entry/src/main/resources/base/element/color.json` | 修改 | 追加 8 个 `home_*` token（浅色值） |
| `entry/src/main/resources/dark/element/color.json` | 修改 | 追加同名 8 个 token（深色值） |
| `entry/src/main/ets/theme/Theme.ets` | 修改 | 追加 `HomeTheme` 类（`$r` 句柄聚合） |
| `entry/src/main/ets/components/ResumeCard.ets` | 新建 | 续听 / 今日推荐二态合一的卡片组件 |
| `entry/src/main/ets/pages/HomePage.ets` | 修改 | `build()` 顶层加 Stack 渐变 + 嵌入 ResumeCard + state 管理 |
| `.gitignore` | 修改 | 忽略 `.superpowers/` 工作目录（brainstorm 服务器产物） |

---

## ArkUI 文档合规规则（每个涉及 ArkUI API 的步骤都必须遵守）

> 详见 [spec §9](docs/superpowers/specs/2026-06-03-homepage-redesign-design.md)。摘要：
>
> 1. 写 ArkUI 代码前，对非显然 API 调一次 `mcp__context7__resolve-library-id` + `mcp__context7__query-docs`，或 `Skill: hmos-arkts-knowledge-retriever`
> 2. **禁用** V1 装饰器（`@State`/`@Prop`/`@Link`/`@ObjectLink`）、字面 hex、index 作 LazyForEach key、TextInput 单向绑定
> 3. 写完一个文件后用 `Skill: hmos-arkts-syntax-checker` 跑一遍编译，零错零警告才算完成
> 4. 文档证据归档到 commit message / PR 描述

---

## Task 1: 注册颜色资源 token（浅色）

**Files:**
- Modify: `entry/src/main/resources/base/element/color.json`

- [ ] **Step 1.1: 读取当前 base 资源全文，确认现有 token**

Run: `cat entry/src/main/resources/base/element/color.json`
Expected: 看到 9 个现有 token（`start_window_background` / `page_background` / `card_background` / `text_*` / `divider` / `input_background`）

- [ ] **Step 1.2: 追加 8 个 home_* token**

把 `entry/src/main/resources/base/element/color.json` 改为下面的内容（保留所有旧 token，仅在数组末尾追加新 token）：

```json
{
  "color": [
    { "name": "start_window_background", "value": "#FFFFFF" },
    { "name": "page_background", "value": "#F5F5F5" },
    { "name": "card_background", "value": "#FFFFFF" },
    { "name": "text_primary", "value": "#1A1A1A" },
    { "name": "text_secondary", "value": "#666666" },
    { "name": "text_tertiary", "value": "#999999" },
    { "name": "text_placeholder", "value": "#BBBBBB" },
    { "name": "divider", "value": "#F0F0F0" },
    { "name": "input_background", "value": "#F0F0F0" },
    { "name": "home_bg_warm_top", "value": "#FFF3E2" },
    { "name": "home_bg_warm_mid", "value": "#FFF9F1" },
    { "name": "home_bg_neutral", "value": "#F5F5F5" },
    { "name": "home_accent", "value": "#FF6B3D" },
    { "name": "home_accent_soft", "value": "#1AFF6B3D" },
    { "name": "home_card_surface", "value": "#FFFFFF" },
    { "name": "home_card_shadow", "value": "#14000000" },
    { "name": "home_progress_track", "value": "#0F000000" }
  ]
}
```

- [ ] **Step 1.3: 验证 JSON 合法**

Run: `node -e "JSON.parse(require('fs').readFileSync('entry/src/main/resources/base/element/color.json'))"`
Expected: 无输出，退出码 0

- [ ] **Step 1.4: 不要在这里 commit**——下个 task 把深色一起加完再一起 commit

---

## Task 2: 注册颜色资源 token（深色）

**Files:**
- Modify: `entry/src/main/resources/dark/element/color.json`

- [ ] **Step 2.1: 追加 8 个 home_* 深色值**

把 `entry/src/main/resources/dark/element/color.json` 改为下面的内容（保留所有旧 token）：

```json
{
  "color": [
    { "name": "start_window_background", "value": "#000000" },
    { "name": "page_background", "value": "#1A1A1A" },
    { "name": "card_background", "value": "#2C2C2C" },
    { "name": "text_primary", "value": "#E8E8E8" },
    { "name": "text_secondary", "value": "#AAAAAA" },
    { "name": "text_tertiary", "value": "#777777" },
    { "name": "text_placeholder", "value": "#555555" },
    { "name": "divider", "value": "#333333" },
    { "name": "input_background", "value": "#333333" },
    { "name": "home_bg_warm_top", "value": "#2A1F14" },
    { "name": "home_bg_warm_mid", "value": "#1F1812" },
    { "name": "home_bg_neutral", "value": "#1A1A1A" },
    { "name": "home_accent", "value": "#FF8A5A" },
    { "name": "home_accent_soft", "value": "#33FF8A5A" },
    { "name": "home_card_surface", "value": "#2C2C2C" },
    { "name": "home_card_shadow", "value": "#33000000" },
    { "name": "home_progress_track", "value": "#1FFFFFFF" }
  ]
}
```

- [ ] **Step 2.2: 验证 JSON 合法 + token 名一一对应**

Run:
```bash
node -e "
const base = JSON.parse(require('fs').readFileSync('entry/src/main/resources/base/element/color.json'));
const dark = JSON.parse(require('fs').readFileSync('entry/src/main/resources/dark/element/color.json'));
const baseHome = base.color.filter(c => c.name.startsWith('home_')).map(c => c.name).sort();
const darkHome = dark.color.filter(c => c.name.startsWith('home_')).map(c => c.name).sort();
console.log('base home tokens:', baseHome.length, baseHome.join(','));
console.log('dark home tokens:', darkHome.length, darkHome.join(','));
console.log('match:', JSON.stringify(baseHome) === JSON.stringify(darkHome));
"
```
Expected: `match: true`，每边 8 个 token

- [ ] **Step 2.3: Commit 资源**

```bash
git add entry/src/main/resources/base/element/color.json entry/src/main/resources/dark/element/color.json
git commit -m "feat(home): 新增 home_* 颜色 token (浅/深双份)

8 个首页业务色:
- home_bg_warm_top/mid/neutral: 暖色背景渐变三档
- home_accent/accent_soft: 暖橙强调色
- home_card_surface/card_shadow: ResumeCard 卡片
- home_progress_track: 进度条轨道

走资源限定符自动深浅切换，零运行时成本。"
```

---

## Task 3: 在 Theme.ets 暴露 HomeTheme 类

**Files:**
- Modify: `entry/src/main/ets/theme/Theme.ets`

- [ ] **Step 3.1: 读取 Theme.ets 现有内容确认末尾位置**

Run: `cat entry/src/main/ets/theme/Theme.ets`
Expected: 末尾是 `AppCurve` 类，闭合 `}` 在第 69 行

- [ ] **Step 3.2: 在文件末尾追加 HomeTheme 类**

在 [theme/Theme.ets](entry/src/main/ets/theme/Theme.ets) 的末尾（`AppCurve` 类闭合 `}` 之后），追加：

```typescript

/**
 * 首页改版颜色聚合（仅 HomePage / ResumeCard 使用）
 * 走 base/dark element/color.json 双份资源，自动深浅切换。
 */
export class HomeTheme {
  static readonly BgWarmTop: Resource = $r('app.color.home_bg_warm_top');
  static readonly BgWarmMid: Resource = $r('app.color.home_bg_warm_mid');
  static readonly BgNeutral: Resource = $r('app.color.home_bg_neutral');
  static readonly Accent: Resource = $r('app.color.home_accent');
  static readonly AccentSoft: Resource = $r('app.color.home_accent_soft');
  static readonly CardSurface: Resource = $r('app.color.home_card_surface');
  static readonly CardShadow: Resource = $r('app.color.home_card_shadow');
  static readonly ProgressTrack: Resource = $r('app.color.home_progress_track');
}
```

> **不动 `AppColor` 类**：字面 hex 字段保持原样，不加 `@deprecated`，避免连坐其它 9 个页面的 review。

- [ ] **Step 3.3: 验证编译**

Run via Skill: `hmos-arkts-syntax-checker`，目标文件：`entry/src/main/ets/theme/Theme.ets`
Expected: 0 error, 0 warning

如有 "Cannot find name '$r'" 类报错，按以下顺序排查：
1. 确认 `Resource` 类型导入：在 `Theme.ets` 顶部如未导入则加 `import { Resource } from '@kit.ArkUI'`（先用 `mcp__context7__query-docs` 确认 6.1 版本路径）
2. `$r()` 是 ArkTS 全局函数，不需要 import；若仍报错改成 getter：`static get BgWarmTop(): Resource { return $r('app.color.home_bg_warm_top'); }`

- [ ] **Step 3.4: Commit Theme 修改**

```bash
git add entry/src/main/ets/theme/Theme.ets
git commit -m "feat(home): Theme.ets 新增 HomeTheme 资源句柄类

8 个 \$r('app.color.home_*') 句柄聚合，供 HomePage / ResumeCard 引用。
AppColor 旧字段保持原样，不连坐 review。"
```

---

## Task 4: 新建 ResumeCard 组件骨架（仅 Empty 模式编译过）

**Files:**
- Create: `entry/src/main/ets/components/ResumeCard.ets`

- [ ] **Step 4.1: 查文档确认 V2 装饰器组合在子组件的写法**

Run via Skill: `hmos-arkts-knowledge-retriever`，查询：`@ComponentV2 @Param @Event @Monitor 子组件 默认值`
预期收获：确认 `@Param` 字段必须有默认值或在父级显式传入；`@Event` 默认值用 `() => {}`；`@Monitor` 监听 `@Param` 字段变化

- [ ] **Step 4.2: 写最小骨架**

新建 [components/ResumeCard.ets](entry/src/main/ets/components/ResumeCard.ets)：

```typescript
import { Book } from '../model/Book';
import { AppFont, AppRadius, AppSpace, HomeTheme } from '../theme/Theme';

export enum ResumeCardMode {
  Empty = 0,
  Resume = 1,
  Suggest = 2,
}

@ComponentV2
export struct ResumeCard {
  @Param mode: ResumeCardMode = ResumeCardMode.Empty;
  @Param book: Book | null = null;
  @Param chapterTitle: string = '';
  @Param progress: number = 0;
  @Event onTapBody: () => void = () => {};
  @Event onTapPlay: () => void = () => {};

  build() {
    if (this.mode === ResumeCardMode.Empty || !this.book) {
      // Empty 态完全不占空间
      Column().height(0).width(0)
    } else {
      this.cardBuilder()
    }
  }

  @Builder
  cardBuilder() {
    Row({ space: AppSpace.Sm }) {
      Text('card placeholder').fontColor($r('sys.color.font_primary'))
    }
    .width('100%')
    .padding(AppSpace.Sm)
    .margin({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Xs })
    .backgroundColor(HomeTheme.CardSurface)
    .borderRadius(AppRadius.Lg)
  }
}
```

- [ ] **Step 4.3: 编译检查**

Run via Skill: `hmos-arkts-syntax-checker`，目标：`entry/src/main/ets/components/ResumeCard.ets`
Expected: 0 error, 0 warning

- [ ] **Step 4.4: Commit 骨架**

```bash
git add entry/src/main/ets/components/ResumeCard.ets
git commit -m "feat(home): 新建 ResumeCard 组件骨架

三态枚举(Empty/Resume/Suggest) + V2 输入参数齐全，build 仅 Empty 态生效。"
```

---

## Task 5: ResumeCard 实现 Resume 模式视觉

**Files:**
- Modify: `entry/src/main/ets/components/ResumeCard.ets`

- [ ] **Step 5.1: 查文档确认 SymbolGlyph 与 shadow 链式 API**

Run via Skill: `hmos-arkts-knowledge-retriever`，查询：`SymbolGlyph 系统图标 sys.symbol.play_fill` 与 `shadow ShadowOptions Resource color`
预期收获：`SymbolGlyph` 第一个参数是 `$r('sys.symbol.*')`、`fontColor` 接受 `Resource[]`；`shadow({ radius, color, offsetY })` 的 `color` 字段类型是 `Color | Resource | string`

- [ ] **Step 5.2: 替换 cardBuilder 为完整 Resume 模式 UI**

把 [components/ResumeCard.ets](entry/src/main/ets/components/ResumeCard.ets) 的 `cardBuilder()` 整段替换为：

```typescript
  @Builder
  cardBuilder() {
    Row({ space: AppSpace.Md }) {
      // 封面
      this.coverBuilder()

      // 文字列
      Column({ space: 4 }) {
        // 顶部小标签
        Text(this.modeLabel())
          .fontSize(AppFont.Caption)
          .fontColor(HomeTheme.Accent)
          .fontWeight(FontWeight.Bold)
          .letterSpacing(1)

        // 主标题（书名）
        Text(this.book?.title ?? '')
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        // 副标题（章节名 / 作者）
        Text(this.subtitle())
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        // 进度条（仅 Resume 模式）
        if (this.mode === ResumeCardMode.Resume) {
          Stack({ alignContent: Alignment.Start }) {
            // track
            Column().width('100%').height(3).borderRadius(2).backgroundColor(HomeTheme.ProgressTrack)
            // fill
            Column().width(`${Math.max(0, Math.min(1, this.progress)) * 100}%`)
              .height(3).borderRadius(2).backgroundColor(HomeTheme.Accent)
          }
          .width('100%')
          .margin({ top: 6 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)

      // 圆形播放按钮
      Stack() {
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(14)
          .fontColor([Color.White])
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor(HomeTheme.Accent)
      .shadow({ radius: 8, color: HomeTheme.CardShadow, offsetY: 2 })
      .onClick(() => this.onTapPlay())
    }
    .width('100%')
    .padding(AppSpace.Sm)
    .margin({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Xs })
    .backgroundColor(HomeTheme.CardSurface)
    .borderRadius(AppRadius.Lg)
    .shadow({ radius: 14, color: HomeTheme.CardShadow, offsetY: 4 })
    .onClick(() => this.onTapBody())
  }

  @Builder
  coverBuilder() {
    if (this.book?.cover && this.book.cover.startsWith('http')) {
      Image(this.book.cover)
        .width(44)
        .height(60)
        .borderRadius(6)
        .objectFit(ImageFit.Cover)
    } else {
      Stack() {
        Column().width('100%').height('100%').backgroundColor(HomeTheme.Accent)
        Text(this.book?.title ? this.book.title.substring(0, 1) : '?')
          .fontSize(18)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
      }
      .width(44)
      .height(60)
      .borderRadius(6)
      .clip(true)
    }
  }

  private modeLabel(): string {
    if (this.mode === ResumeCardMode.Resume) return '继续收听';
    if (this.mode === ResumeCardMode.Suggest) return '今日推荐';
    return '';
  }

  private subtitle(): string {
    if (this.mode === ResumeCardMode.Resume) {
      return this.chapterTitle || '继续上次播放';
    }
    if (this.mode === ResumeCardMode.Suggest && this.book) {
      const author = this.book.author || '未知';
      const narrator = this.book.narrator;
      return narrator ? `${author} · ${narrator}` : author;
    }
    return '';
  }
```

- [ ] **Step 5.3: 编译检查**

Run via Skill: `hmos-arkts-syntax-checker`，目标：`entry/src/main/ets/components/ResumeCard.ets`
Expected: 0 error, 0 warning

如报 `sys.symbol.play_fill` 不存在，改为 `sys.symbol.play`（基础符号库一定有）。

- [ ] **Step 5.4: Commit**

```bash
git add entry/src/main/ets/components/ResumeCard.ets
git commit -m "feat(home): ResumeCard 实现 Resume/Suggest 双模式视觉

- 封面 44x60 + 文字列 + 圆形播放按钮
- Resume 模式带进度条; Suggest 模式不显示进度
- 颜色全部走 HomeTheme.*, 自动深浅切换"
```

---

## Task 6: HomePage 引入 HomeTheme 与 ResumeCard imports

**Files:**
- Modify: `entry/src/main/ets/pages/HomePage.ets:1-15`

- [ ] **Step 6.1: 读取 HomePage 顶部当前 import 段**

Run: `head -20 entry/src/main/ets/pages/HomePage.ets`

- [ ] **Step 6.2: 修改 imports**

把 `entry/src/main/ets/pages/HomePage.ets` 的第 5 行 import：

```typescript
import { AppRadius, AppSpace, AppFont, AppMotion, AppCurve } from '../theme/Theme';
```

改为：

```typescript
import { AppRadius, AppSpace, AppFont, AppMotion, AppCurve, HomeTheme } from '../theme/Theme';
```

并在 import `BookCard` 的下一行（紧跟 `import { BookCard } from '../components/BookCard';`）追加：

```typescript
import { ResumeCard, ResumeCardMode } from '../components/ResumeCard';
```

也加 `PreferenceService`（因为后面要用 `getLastPlayed()`）。在文件 imports 段末尾追加：

```typescript
import { PreferenceService } from '../service/PreferenceService';
import { DataService } from '../service/DataService';
import { AppStorageV2 } from '@kit.ArkUI';
import { PlayerState, PLAYER_STATE_KEY } from '../model/PlayerState';
import { common } from '@kit.AbilityKit';
```

> 说明：HomePage 当前没有引用 PlayerState；本计划要在它身上 `@Monitor` 监听 `playerState.currentBook`，故新增 imports。

- [ ] **Step 6.3: 编译检查**

Run via Skill: `hmos-arkts-syntax-checker`，目标：`entry/src/main/ets/pages/HomePage.ets`
Expected: 0 error, 仅允许"未使用 import"警告（因为还没用上，下个 task 会用）

> 不 commit，等 Task 7 一起。

---

## Task 7: HomePage 新增 resume state + loadResumeState() 方法

**Files:**
- Modify: `entry/src/main/ets/pages/HomePage.ets`

- [ ] **Step 7.1: 在 `@ComponentV2` struct 内、`@Local audioBooks: Book[] = [];` 之前插入 resume state**

定位 `entry/src/main/ets/pages/HomePage.ets:24` 那行 `@Local audioBooks: Book[] = [];`，在它前面插入：

```typescript
  @Local resumeMode: ResumeCardMode = ResumeCardMode.Empty;
  @Local resumeBook: Book | null = null;
  @Local resumeChapterTitle: string = '';
  @Local resumeProgress: number = 0;
  /** 全局播放状态（监听 currentBook 变化触发续听卡刷新） */
  @Local playerState: PlayerState = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;

```

- [ ] **Step 7.2: 在 class 末尾、最后一个方法的 `}` 之前，添加 `loadResumeState()` 与 `@Monitor`**

定位 [HomePage.ets:639-709](entry/src/main/ets/pages/HomePage.ets#L639-L709) 的 `buildListItem(book: Book)` 方法之后、整个 struct 闭合 `}` 之前，添加：

```typescript

  @Monitor('playerState.currentBook')
  onCurrentBookChange(): void {
    this.loadResumeState();
  }

  private async loadResumeState(): Promise<void> {
    // 1) 优先：lastPlayed 还原
    try {
      const last = await PreferenceService.getLastPlayed();
      if (last && last.bookId) {
        const book = await this.restoreBookById(last.bookId);
        if (book) {
          this.resumeBook = book;
          this.resumeChapterTitle = last.chapterTitle ?? '';
          const dur = last.durationMs ?? 0;
          this.resumeProgress = dur > 0 ? Math.max(0, Math.min(1, last.progressMs / dur)) : 0;
          this.resumeMode = ResumeCardMode.Resume;
          return;
        }
      }
    } catch (_e) {
      // 还原失败兜底走 Suggest
    }

    // 2) 兜底：homeBlocks[0].books[0] → Suggest
    if (this.homeBlocks.length > 0 && this.homeBlocks[0].books.length > 0) {
      const r = this.homeBlocks[0].books[0];
      this.resumeBook = this.homeBookFromResult(r);
      this.resumeChapterTitle = '';
      this.resumeProgress = 0;
      this.resumeMode = ResumeCardMode.Suggest;
      return;
    }

    // 3) 都没有：Empty
    this.resumeMode = ResumeCardMode.Empty;
    this.resumeBook = null;
  }

  private async restoreBookById(bookId: string): Promise<Book | null> {
    // 优先内存 SearchCache（同步，最快）
    const cached = SearchCache.get(bookId);
    if (cached) return cached;
    // 兜底走 DataService（覆盖收藏 / 历史 / cachedBooks）
    try {
      const ctx = this.getUIContext()?.getHostContext() as common.UIAbilityContext | undefined;
      if (!ctx) return null;
      const found = await DataService.getBookById(ctx, bookId);
      return found ?? null;
    } catch (_e) {
      return null;
    }
  }

  private onResumeBodyTap(): void {
    if (!this.resumeBook) return;
    this.onBookTap(this.resumeBook.id);
  }

  private onResumePlayTap(): void {
    if (!this.resumeBook) return;
    // Resume 模式带 progress 续播；Suggest 模式仅路由（详情页负责后续）
    // 路由仍走 onBookTap 回调，progressMs 由 PlaybackStore + 详情页恢复，
    // 与现有"返回首页继续播"路径一致，避免引入新事件协议。
    this.onBookTap(this.resumeBook.id);
  }
```

- [ ] **Step 7.3: 在 `aboutToAppear` 末尾追加调用，在 `loadHomeBlocks` 流式回调里追加兜底重算**

定位 [HomePage.ets:57-63](entry/src/main/ets/pages/HomePage.ets#L57-L63) 的 `aboutToAppear` 方法。

在该方法的 `this.onScrollerReady(this.contentScroller);` 那行之后追加：

```typescript
    this.loadResumeState();
```

定位 [HomePage.ets:79-105](entry/src/main/ets/pages/HomePage.ets#L79-L105) 的 `loadHomeBlocks` 方法。

在 `streamAllHomeBlocks` 的回调内（`this.loadingHome = false;` 这行之后），追加：

```typescript
        // 首板块到货 → 触发 Suggest 兜底（如果当前是 Empty）
        if (this.resumeMode === ResumeCardMode.Empty) {
          this.loadResumeState();
        }
```

- [ ] **Step 7.4: 编译检查**

Run via Skill: `hmos-arkts-syntax-checker`，目标：`entry/src/main/ets/pages/HomePage.ets`
Expected: 0 error, 0 warning

> 不 commit，等 Task 8 把 build 接进来一起。

---

## Task 8: HomePage build() 顶层加 Stack 渐变背景

**Files:**
- Modify: `entry/src/main/ets/pages/HomePage.ets:250-457`

- [ ] **Step 8.1: 查文档确认 Stack alignContent 枚举与 expandSafeArea 参数**

Run via Skill: `hmos-arkts-knowledge-retriever`，查询：`Stack alignContent Alignment.TopStart linearGradient angle colors expandSafeArea SafeAreaType SafeAreaEdge`
预期收获：
- `Alignment.TopStart` 是合法枚举
- `linearGradient({ angle, colors: [[Resource, number], ...] })`，元组 `[color, position 0~1]`
- `expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])`

- [ ] **Step 8.2: 重构 build()**

定位 [HomePage.ets:250-434](entry/src/main/ets/pages/HomePage.ets#L250-L434) 的整个 `build()` 方法。

把 `build() { HdsNavigation() { ... }.titleBar(...).bindToScrollable(...).titleMode(...).hideBackButton(...) }` 整段，替换为下面的结构（**注意：内层 HdsNavigation 配置原封不动，外面包一层 Stack + 渐变 Column**）：

```typescript
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // L0 暖色渐变背景（满屏，覆盖状态栏区域）
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

      // L1 原 HdsNavigation（保持配置不动）
      HdsNavigation() {
        Refresh({ refreshing: this.pullRefreshing!!, builder: this.refreshHeader() }) {
          List({ scroller: this.contentScroller }) {
            // === 原有所有 ListItem 一字不差搬过来 ===
            // ⬇️ Step 8.3 单独说明 ResumeCard ListItem 插入位置
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .backgroundColor(Color.Transparent)  // ← 新增:让 L0 暖色透出
          .onScroll(() => {
            const offset = this.contentScroller.currentOffset().yOffset;
            const delta = offset - this.lastScrollOffset;
            const THRESHOLD = 6;
            if (offset <= 0 || delta < -THRESHOLD) {
              if (this.currentCollapsed) {
                this.currentCollapsed = false;
                this.onScrollDirection(false);
              }
            } else if (delta > THRESHOLD) {
              if (!this.currentCollapsed) {
                this.currentCollapsed = true;
                this.onScrollDirection(true);
              }
            }
            this.lastScrollOffset = offset;
          })
          .cachedCount(5)
          .clip(false)
        }
        .onRefreshing(() => this.onPullRefresh())
        .refreshOffset(64)
        .pullToRefresh(true)
      }
      .titleBar({
        content: {
          title: { mainTitle: '首页' }
        },
        style: {
          scrollEffectOpts: {
            enableScrollEffect: true,
            scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
            enableRefreshOffsetChange: true,
            blurEffectiveStartOffset: LengthMetrics.vp(0),
            blurEffectiveEndOffset: LengthMetrics.vp(20)
          },
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          }
        },
        enableComponentSafeArea: true
      })
      .bindToScrollable([this.contentScroller])
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
```

> **关键**：把原 build 内的 `List(...) { ... }` 整块（即原第 253-411 行）原样搬到上面注释处。下个 step 单独把 ResumeCard ListItem 插进去。

- [ ] **Step 8.3: 在 List 内插入 ResumeCard ListItem**

在原 `// 第1项：搜索框 + (条件) 工具栏` 那个 ListItem 闭合 `}` 之后、`// 第2~N项：内容主体` 之前，插入：

```typescript
        // 第1.5项：续听卡 / 今日推荐（推荐态 + 非 Empty 时显示）
        if (!this.hasSearched && this.resumeMode !== ResumeCardMode.Empty) {
          ListItem() {
            ResumeCard({
              mode: this.resumeMode,
              book: this.resumeBook,
              chapterTitle: this.resumeChapterTitle,
              progress: this.resumeProgress,
              onTapBody: () => this.onResumeBodyTap(),
              onTapPlay: () => this.onResumePlayTap()
            })
          }
        }
```

- [ ] **Step 8.4: 编译 + 完整构建**

Run via Skill: `hmos-arkts-syntax-checker`，目标：`entry/src/main/ets/pages/HomePage.ets`
Expected: 0 error, 0 warning

如果出现 V1/V2 装饰器混用或 `@Param` 默认值类型推断不一致报错，立即用 `hmos-arkts-knowledge-retriever` 查 `@Param Book 可空类型`，按文档调整。

- [ ] **Step 8.5: 跑一次完整 build**

Run via Skill: `hmos-arkts-syntax-checker`，目标整个 `entry` 模块（不传 files 参数）
Expected: assembleHap 成功，HAP 产物落到 `entry/build/.../entry-default-signed.hap`

- [ ] **Step 8.6: Commit HomePage**

```bash
git add entry/src/main/ets/pages/HomePage.ets
git commit -m "feat(home): 重做首页布局为暖色沉浸 + 续听卡

- build() 顶层 Stack 包暖色 linearGradient 背景层 (L0),
  HdsNavigation 在其上 (L1), titleBar GRADIENT_BLUR + ADAPTIVE 维持不变
- mainTitle 从空字符串改为 '首页', titleMode MINI 不变
- List 设 backgroundColor(Transparent) 让 L0 透出
- 父 Stack expandSafeArea([SYSTEM],[TOP]) 让暖色铺到状态栏

新增 ResumeCard 集成:
- @Local resumeMode/Book/ChapterTitle/Progress 四个状态字段
- @Monitor playerState.currentBook 触发刷新
- loadResumeState 三段决策: lastPlayed → SearchCache/DataService → 兜底 Suggest
- aboutToAppear 与 loadHomeBlocks 流式回调里都触发一次"

```

---

## Task 9: 把 .superpowers 加进 .gitignore

**Files:**
- Modify: `.gitignore`

- [ ] **Step 9.1: 读取当前 .gitignore**

Run: `cat .gitignore | grep -E "superpowers|brainstorm" || echo "未配置"`

如果输出 "未配置"，继续；否则跳过此 task。

- [ ] **Step 9.2: 追加 ignore 规则**

在 `.gitignore` 末尾追加一行：

```
.superpowers/
```

- [ ] **Step 9.3: Commit**

```bash
git add .gitignore
git commit -m "chore: ignore .superpowers/ (brainstorming server workdir)"
```

---

## Task 10: 真机/模拟器视觉验证

**Files:** 无代码改动

- [ ] **Step 10.1: 出 HAP 并安装到设备**

Run via Skill: `hmos-arkts-syntax-checker`（或 `mcp__deveco__build_project`），构建 debug HAP。

如有可用设备，用 `mcp__deveco__start_app` 启动应用。

- [ ] **Step 10.2: 浅色模式人工核验清单**

打开应用首页，目测：
- [ ] 顶部"首页"大字标题清晰
- [ ] 顶部到中段是暖色渐变（橙偏米色 → 浅米色 → 中性灰）
- [ ] 续听卡（如有 lastPlayed）：白底卡 + 橙色"继续收听"标签 + 播放按钮 + 进度条
- [ ] 上滑：标题栏 GRADIENT_BLUR 模糊过渡平滑，无白边、无颜色断层
- [ ] 续听卡阴影柔和可见
- [ ] 横向板块卡片在暖色背景上不刺眼

- [ ] **Step 10.3: 深色模式人工核验清单**

切系统到深色（设置 → 显示和亮度 → 深色），不重启应用：
- [ ] 首页颜色立即跟随切换（资源限定符行为）
- [ ] 顶部是低饱和暖棕色而非纯黑
- [ ] 续听卡背景为深灰，"继续收听"标签为提亮的暖橙（`#FF8A5A`）
- [ ] 进度条 fill 在深色 track 上对比度足够
- [ ] 状态栏字色自动反转（白字）

- [ ] **Step 10.4: 续听卡三态核验**

| 场景 | 期望 |
|---|---|
| 装好 + 还没听过任何书 | 显示"今日推荐"卡（来自首板块第一本）|
| 听过书后回到首页 | 显示"继续收听"卡 + 进度条 + 章节名 |
| 没续听 + 没书源板块（清空所有书源） | 续听卡区域不占空间 |
| 在书架点书 → 播放 → 返回首页 | 续听卡立即更新为这本书 |

- [ ] **Step 10.5: 验收记录**

在 commit message 或 PR 描述里记录截图（浅色 / 深色各一张）+ 三态截图。

如有 §8 风险表中的问题（双重避让 / 暖色被压住 / 性能掉帧），按表中"回退方案"处理。

---

## Task 11: 补编译 + 模块级冒烟

- [ ] **Step 11.1: 全量构建验证**

Run via Skill: `hmos-arkts-syntax-checker`，整 module 编译
Expected: 编译成功，HAP 产物正常

- [ ] **Step 11.2: 检查未引入新依赖**

Run: `git diff main -- entry/oh-package.json oh-package.json`
Expected: 无 diff 或仅与本计划无关的现有 diff

- [ ] **Step 11.3: 检查改动范围合规**

Run: `git diff main --stat -- entry/src/main/ets/components/ResumeCard.ets entry/src/main/ets/pages/HomePage.ets entry/src/main/ets/theme/Theme.ets entry/src/main/resources/base/element/color.json entry/src/main/resources/dark/element/color.json .gitignore`
Expected: 仅这 6 个文件有改动，每个文件都符合本计划描述

如果 `git diff main --stat` 显示其它文件被改了（如 PlayerPage.ets / SourcePage.ets），说明触发了 §6 "不在范围内" 红线，需要 revert。

---

## 自检清单（计划写完后跑一遍）

- [x] 每个 ArkUI 改动前都有"先查文档"step（Task 4 / 5 / 8 都有）
- [x] 每个文件改完都有 `hmos-arkts-syntax-checker` 编译检查
- [x] 没用 V1 装饰器
- [x] 没字面 hex（颜色全部 `HomeTheme.*` 或 `$r('sys.color.*')`，唯一例外是 ResumeCard 内 `Color.White` 给前景图标，合法）
- [x] 没 index 作为 LazyForEach key（本计划未引入新的 LazyForEach；ResumeCard 的 ListItem 是单条，不需要 key）
- [x] spec §1-§9 每节都有对应 Task：
  - §1 页面结构 → Task 8
  - §2 ResumeCard → Task 4 + Task 5
  - §3 HomePage 集成（state/decision tree/列表项）→ Task 6 + Task 7 + Task 8.3
  - §4 视觉系统 → Task 1 + Task 2 + Task 3 + Task 8（Stack 渐变 + List 透明）
  - §5 数据流 → Task 7 (loadResumeState)
  - §6 不做清单 → Task 11.3 校验改动范围
  - §7 验收 → Task 10
  - §8 风险与回退 → Task 10 验证步骤覆盖
  - §9 文档合规 → 每个 ArkUI 任务都嵌入查文档 step
- [x] 改动文件清单与 spec §7 实现边界一致（HomePage / Theme / ResumeCard / 两份 color.json + .gitignore）
- [x] 没有空泛步骤（每个 step 都有具体代码 / 命令 / 期望输出）
