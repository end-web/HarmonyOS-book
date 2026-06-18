# 阅读功能开发参考：Reader Kit 与翻页能力

> 生成时间：2026-06-15  
> 参考来源：华为开发者联盟官方文档  
> - Reader Kit 简介：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/reader-introduction  
> - 阅读翻页方式调节：https://developer.huawei.com/consumer/cn/doc/architecture-guides/page_flip_page-0000002271210553

## 1. 官方文档核心结论

### 1.1 Reader Kit 能力范围

Reader Kit（阅读服务）提供多格式电子书解析、排版、阅读交互能力，适合快速搭建完整阅读器。

官方明确支持的核心能力：

- **多格式解析**：支持 `txt`、`epub`、`mobi`、`azw`、`azw3`，可获取书名、作者、封面、目录和目录对应正文。
- **文本与富文本排版**：支持标准 `txt`、富文本内容（`html + css`）按仿真翻页、横滑方式分页排版，并提供排版快照和排版信息。
- **阅读页组件**：`ReadPageComponent` 支持书籍排版内容显示、多种翻页交互、翻页动效，以及阅读进度和行为感知。

主要概念：

- `ReadPageComponent`：Reader Kit 封装的 ArkTS 阅读页 UI 组件。
- `bookParser` / `BookParser`：电子书解析引擎，负责解析 `txt`、`epub`、`mobi`、`azw`、`azw3`。
- `spine` / `SpineItem`：定义书籍内容阅读顺序，每个 `SpineItem` 表示一个可阅读内容节点。

### 1.2 Reader Kit 约束

落地时必须优先处理这些限制：

- 只支持**本地文件**，不支持在线文件流。
- 不同书籍文件需要放在应用沙箱下的不同目录。
- 不提供 DRM 保护能力。
- 非标准格式电子书解析可能抛异常，必须捕获并兜底。
- 排版引擎和交互能力需要配套 `ReadPageComponent` 使用。
- Reader Kit 仅适用于 HarmonyOS NEXT 5.0.4 及以上版本的 Phone、PC/2in1、Tablet。
- 当前仅在中国境内提供服务，不含香港特别行政区、澳门特别行政区、中国台湾。
- 官方说明 Reader Kit 暂不支持模拟器。

### 1.3 官方翻页方案

官方“阅读翻页方式调节”实践把翻页分成三类：

| 翻页方式 | 推荐技术 | 适用场景 |
| --- | --- | --- |
| 左右翻页 | `Swiper` + `LazyForEach` | 自研分页、简单横向切页 |
| 上下翻页 | `List` + `LazyForEach` / `ListItem` | 连续纵向阅读、章节流阅读 |
| 仿真翻页 | Reader Kit API + `ReadPageComponent` | 更完整的阅读器体验、仿真动效、Reader Kit 排版 |

官方示例约束：

- 示例支持 API Version 20 Release 及以上。
- 示例支持 HarmonyOS 6.0.0 Release SDK 及以上。
- 示例需要 DevEco Studio 6.0.0 Release 及以上编译运行。

注意：这是官方示例工程约束；Reader Kit 能力本身的设备限制按 Reader Kit 文档为准。

## 2. ListenBook 当前代码映射

当前项目已经有阅读相关基础能力：

| 模块 | 当前职责 |
| --- | --- |
| `entry/src/main/ets/pages/ReaderPage.ets` | 已接入 `@kit.ReaderKit`，使用 `ReadPageComponent`、`ReaderComponentController`、`ReaderSetting`、`bookParser.getDefaultHandler()` |
| `entry/src/main/ets/service/ReaderService.ets` | 负责获取书籍、补齐目录、抓取正文、拆分段落，并把章节正文写入沙箱 `txt` 文件 |
| `entry/src/main/ets/pages/BookDetailPage.ets` | 根据书籍类型进入播放或阅读，并把 `bookId`、章节恢复参数传入 `ReaderPage` |
| `entry/src/main/ets/service/PreferenceService.ets` | 保存历史、阅读进度、缓存书籍等本地数据 |
| `entry/src/main/ets/service/ChapterCacheService.ets` | 已用于章节预加载，可继续复用到阅读章节正文预取 |

当前实现路线与 Reader Kit 官方限制是匹配的：在线来源章节正文先通过 `BookSourceService.getTextContent()` 拉取和清洗，再由 `ReaderService.writeChapterTxt()` 写入应用沙箱，最后交给 `bookParser.getDefaultHandler(path)` 解析。

## 3. 页面 → 接口/服务 → 数据结构

### 3.1 页面结构

| 页面/组件 | 功能 |
| --- | --- |
| `BookDetailPage` | 展示书籍信息、章节列表、继续阅读入口 |
| `ReaderPage` | 阅读主页面，承载 `ReadPageComponent` |
| `ReaderPage` 顶部栏 | 返回、书名、当前章节标题 |
| `ReaderPage` 底部栏 | 进度、上一章、目录、设置、下一章 |
| 目录 Sheet | 当前书籍章节列表，点击切换章节 |
| 设置 Sheet | 字号、主题、翻页模式 |

后续如要补齐三种官方翻页方式，可在 `ReaderPage` 内抽象阅读模式：

- `emulation`：Reader Kit 仿真翻页。
- `horizontal`：Reader Kit 横滑，或自研 `Swiper`。
- `vertical`：自研 `List` 纵向滚动。

### 3.2 服务接口

建议保持当前轻量服务结构，不引入复杂架构。

| 服务方法 | 入参 | 出参 | 说明 |
| --- | --- | --- | --- |
| `ReaderService.getBook(context, bookId)` | `UIAbilityContext`, `bookId` | `Book \| null` | 从搜索缓存或本地缓存取书 |
| `ReaderService.ensureChapters(book)` | `Book` | `Book` | 若章节为空，从书源拉目录并写缓存 |
| `ReaderService.loadContent(book, chapter, nextChapter?)` | `Book`, `Chapter` | `string[]` | 拉取并拆分章节正文 |
| `ReaderService.loadChapterText(book, chapter, nextChapter?)` | `Book`, `Chapter` | `string` | 拼接成适合 Reader Kit 的 txt 正文 |
| `ReaderService.writeChapterTxt(context, book, chapter, text)` | 上下文、书、章节、正文 | `filePath` | 写入沙箱 txt，供 `bookParser` 解析 |
| `PreferenceService.saveProgress(progress)` | 阅读进度 | `void` | 保存章节、`domPos`、更新时间 |
| `PreferenceService.upsertHistory(history)` | 历史记录 | `void` | 更新最近阅读记录 |

### 3.3 数据结构

当前不需要后端数据库。继续使用本地 `Preferences` / 缓存即可。

建议阅读进度最小字段：

```ts
interface ReaderProgress {
  bookId: string;
  chapterId: string;
  chapterTitle: string;
  chapterIndex: number;
  domPos: string;
  updatedAt: number;
}
```

如后续支持完整电子书文件（`epub`、`mobi`、`azw`、`azw3`），建议扩展：

```ts
interface LocalReaderProgress {
  bookId: string;
  filePath: string;
  spineIndex: number;
  domPos: string;
  updatedAt: number;
}
```

在线章节和完整电子书的进度保存不要混用：

- 在线章节书：以 `chapterId + domPos` 恢复。
- 本地完整书：以 `spineIndex + domPos` 恢复。

## 4. 推荐实施路线

### 4.1 优先保留当前 Reader Kit 路线

当前 `ReaderPage` 已经走 Reader Kit，建议继续完善：

1. 在线章节正文继续写入沙箱 `txt`。
2. 使用 `bookParser.getDefaultHandler(filePath)` 解析沙箱文件。
3. 使用 `ReaderComponentController.registerBookParser(handler)` 注册解析器。
4. 使用 `ReaderComponentController.startPlay(spineIndex, domPos)` 打开章节。
5. 监听 `pageShow`，在 `PAGE_ON_SHOW` 时保存 `startDomPos` 和页脚信息。
6. 切章前后调用 `releaseBook()`，避免旧书状态残留。

### 4.2 翻页模式建议

短期建议：

- 仿真翻页：继续使用 Reader Kit `flipMode = '0'`。
- 平移翻页：继续使用 Reader Kit `flipMode = '1'`。

中期如果要补齐官方三模式：

- 左右翻页：如果 Reader Kit 横滑体验满足需求，优先复用 Reader Kit；如果要自定义整页 UI，再用 `Swiper`。
- 上下翻页：Reader Kit 不适合时，用 `List` + 预分页/段落流实现。
- 仿真翻页：保留 Reader Kit，不建议自研仿真动效。

### 4.3 本地完整电子书支持

当前在线章节桥接到 `txt` 是合理方案；若支持用户导入完整电子书：

1. 导入时将文件复制到应用沙箱，按书籍单独目录存放。
2. 原始格式是 `txt`、`epub`、`mobi`、`azw`、`azw3` 时，直接交给 `bookParser.getDefaultHandler(filePath)`。
3. 用 `BookParser` 读取书名、作者、封面、目录，写入本地书籍模型。
4. 阅读进度用 `spineIndex + domPos` 保存。
5. 非标准文件解析异常时，提示“文件格式不标准或暂不支持”。

## 5. 风险与注意事项

- **Reader Kit 权限/服务开通**：若出现 `1016910004`，优先检查 AppGallery Connect 是否为当前应用开通“阅读服务”。
- **模拟器不可作为最终依据**：Reader Kit 官方说明暂不支持模拟器，需要真机验证。
- **区域限制**：海外或港澳台环境可能无法使用 Reader Kit 服务。
- **文件路径限制**：必须使用应用沙箱下本地文件，不要直接传网络 URL。
- **章节文件管理**：当前一章一 txt 文件可快速落地；后续可按书籍目录组织，并增加过期清理。
- **进度恢复**：在线目录可能重排，恢复时应同时参考 `chapterId` 和 `chapterTitle`，当前 `DataService.resolveChapterIndex()` 方向是对的。
- **字体与主题**：Reader Kit 支持系统字体和自定义字体，当前先用系统字体即可，后续再接入用户字体文件。

## 6. 下一步开发清单

- 确认 AGC 阅读服务已开通，并在真机上验证 `ReaderPage` 可打开。
- 补齐 Reader Kit 错误码映射，给用户更明确的失败原因。
- 将 `ReaderService.writeChapterTxt()` 改为按书籍目录存放章节文件，便于清理。
- 增加阅读设置持久化：字号、主题、翻页模式。
- 增加上下滚动阅读模式时，再单独实现 `List` 阅读组件，避免影响当前 Reader Kit 主链路。
- 支持完整本地电子书导入时，新增 `spineIndex` 维度的进度模型。
