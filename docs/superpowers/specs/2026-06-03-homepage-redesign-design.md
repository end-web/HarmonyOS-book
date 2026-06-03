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

| 属性 | 值 |
|---|---|
| 外边距 | `margin: { left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Xs }` |
| 内边距 | `padding: AppSpace.Sm` |
| 背景 | `Color.White` + `shadow({ radius: 14, color: '#0F000000', offsetY: 4 })` |
| 圆角 | `AppRadius.Lg` (16) |
| 高度 | 内容自适应，约 76vp |
| 封面 | 44×60vp，圆角 6vp，带柔和 drop-shadow |
| 圆形播放按钮 | 32×32vp，背景 `HomeTheme.Accent`，白色 `▶` 图标，shadow 同卡片 |
| 进度条（仅 Resume 模式） | 高 3vp，圆角 2vp，bg `#0F000000`，fill `HomeTheme.Accent` |
| 标签文字（"继续收听"/"今日推荐"）| `AppFont.Caption (12)`，颜色 `HomeTheme.Accent`，字重 700，letterSpacing 1 |

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

### 4.1 新增主题 token（仅 HomePage 用）

在 [theme/Theme.ets](entry/src/main/ets/theme/Theme.ets) 新增 `HomeTheme` 类，**不改动现有 `AppColor.Brand`**，避免污染其他页面：

```typescript
export class HomeTheme {
  // 暖色渐变背景（页面整体）
  static readonly BgGradient: LinearGradientOptions = {
    angle: 180,
    colors: [['#FFF8F3', 0], ['#FFEEDE', 0.3], ['#FFFFFF', 1.0]]
  };

  // 暖色强调色（续听标签、播放按钮、进度条）
  static readonly Accent: string = '#FF6B3D';
  static readonly AccentSoft: string = '#1AFF6B3D';   // 10% 透明
}
```

### 4.2 应用范围

| 元素 | 颜色 |
|---|---|
| 页面背景（List 容器） | `linearGradient(HomeTheme.BgGradient)` |
| ResumeCard "继续收听" / "今日推荐" 标签 | `HomeTheme.Accent` |
| ResumeCard 播放按钮背景 | `HomeTheme.Accent` |
| ResumeCard 进度条 fill | `HomeTheme.Accent` |
| 其他（loading、搜索按钮、底部 Tab 选中等） | 保持 `$r('sys.color.brand')` |

### 4.3 标题区

利用现有 HdsNavigation 的 `GRADIENT_BLUR` 效果，把 `title.mainTitle` 从空字符串改成 `'首页'`。`titleMode` 维持 `MINI` 不变（保持现有滚动收缩行为，不引入新模式风险）。

副标题 "已启用 X 个书源" **不**挂在 `HdsNavigation.title` 上（HdsNavigation `subTitle` API 在本项目未验证使用），改为放在第一个 `ListItem` 顶部的 Search 上方，作为一行小字（`AppFont.Caption`、`sys.color.font_tertiary`）。这样跟系统标题区脱耦，行为可控。

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

- 不改 `AppColor.Brand` 全局色（其他页面保持蓝色品牌）
- 不引入"每周一书"等需要本地策划逻辑的板块
- 不改 [SearchPage / 搜索结果展示](entry/src/main/ets/pages/HomePage.ets#L307-L345)（搜索态 UI 维持现状）
- 不改 BookCard / 横向板块 buildHomeBlock 的视觉
- 不做 Hero / Banner / Swiper 轮播
- 不动暗色模式适配（`HomeTheme.BgGradient` 当前仅按浅色给值；暗色下 List 背景透明回退到系统色，由后续单独 PR 处理）

---

## 7. 验收标准

- 有续听记录时：首屏第一眼看到"继续收听"卡，封面 + 章节名 + 进度条，点 ▶ 直接续播
- 无续听记录但有书源板块时：首屏第一眼看到"今日推荐"卡（来自首板块第一本）
- 无续听 + 无书源板块时：续听卡区域完全不占空间，跟现在的空态体验一致
- 滚动到顶部时大字标题"首页"完整显示，下滑后系统自动应用 GRADIENT_BLUR 模糊效果（`titleMode: MINI` 保持不变）
- 暖色渐变背景与现有横向板块卡片不冲突
- 整体改动只触及：[HomePage.ets](entry/src/main/ets/pages/HomePage.ets)、[theme/Theme.ets](entry/src/main/ets/theme/Theme.ets)，新增 [components/ResumeCard.ets](entry/src/main/ets/components/ResumeCard.ets)
