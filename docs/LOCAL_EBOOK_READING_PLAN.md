# 本地电子书升级实施计划

状态：V2 实施方案，阶段 0 技术验证待完成，业务代码尚未开始。

更新日期：2026-08-11

## 0. 执行结论

本次升级在现有 ListenBook 音频 App 中增加本地 EPUB 阅读能力，不改变现有音频内容架构，不增加客户端阅读规则引擎，也不要求服务端提供电子书接口。

方案可以进入开发，但必须先完成 ReaderKit 真机技术验证。只有阶段 0 的编译、解析、翻页、进度恢复和生命周期测试全部通过，才进入数据层和正式页面开发。

首版完整链路：

```text
系统文件选择器
  -> ImportPage 判断导入类型
  -> EPUB 复制到沙箱暂存目录
  -> SHA-256 去重与 ReaderKit 解析
  -> 文件原子落位 + RDB 写入
  -> FavoritePage 统一书架展示
  -> EBookDetailPage
  -> ReaderPage 阅读、翻页、恢复进度
  -> Bookmark / ReadingStats 持久化
```

关键架构决策：

- 音频 `Book`、`Chapter` 和电子书 `EBook`、`ReadingPosition` 完全分离。
- 书架只在展示层聚合两种内容，持久化层不建立音频与电子书共用大模型。
- EPUB 原文件保存在应用沙箱；ReaderKit 只读取已复制到沙箱的文件。
- 电子书元数据、进度、书签和按日阅读时长使用独立 RDB。
- 阅读器控制器归 `ReaderPage` 生命周期所有，不做全局单例。
- 首版不备份 EPUB、电子书元数据、进度和书签，避免恢复出无法打开的孤立记录。
- 首版不包含任何服务端和 HTTP API 变更。

## 1. 目标与范围

### 1.1 用户目标

用户可以从系统文件中导入一本 EPUB，在现有书架中识别并打开它，获得稳定、安静、可恢复的本地阅读体验，同时不影响听书、下载、播放和在线书源功能。

### 1.2 首版包含

- 单个 EPUB 文件导入
- 自动读取书名、作者、封面和目录
- 导入文件 SHA-256 去重
- 书架“全部 / 听书 / 电子书”筛选
- 兼容现有书架网格和列表两种视图
- 电子书详情页
- 开始阅读、继续阅读
- 目录跳转、左右点击翻页和 ReaderKit 原生手势
- 字体、字号、行距、翻页方式和阅读主题
- 跟随系统深浅模式
- 阅读位置保存和异常恢复
- 当前页书签、书签列表和书签跳转
- 按日阅读时长、最近阅读时间和阅读历史
- 删除电子书并清理文件、进度、书签和统计
- 损坏文件、重复文件、空间不足和 ReaderKit 初始化失败提示

### 1.3 首版不包含

- 在线电子书源、电子书商店和服务端电子书接口
- EPUB 文件或阅读进度云同步
- PDF、TXT、MOBI、AZW3 等其他格式
- DRM 加密电子书
- 全文搜索
- 划线、批注、想法和社交功能
- TTS 朗读和音画同步
- 跨设备继续阅读
- 用户导入 Legado/Reader 文本规则

### 1.4 成功标准

- 一份合法 EPUB 可以在 API 26 真机完成导入、打开、翻页和目录跳转。
- 退出页面、杀进程和重新启动后可以恢复到同一正文位置。
- 更改字体、字号、行距和窗口尺寸后仍以 DOM 位置恢复，不依赖旧页码。
- 电子书加入后不会改变现有音频导入、收藏、播放、下载和书源刷新行为。
- 任一导入或删除步骤失败后，不留下可见的半成品记录。

## 2. 当前工程基线

实现时必须以当前主分支为基线，不按照旧版文本阅读器代码恢复功能。

- `Book.contentType = text` 仅表示升级前遗留记录，当前书架会过滤这类内容。
- `ImportPage` 当前只处理音频文件和音频 ZIP，最多选择 50 个文件。
- `FavoritePage` 当前支持网格/列表切换、拖动删除、在线书刷新和音频播放进度展示。
- `Index.ets` 使用 `NavPathStack` 和集中式 `routerMap` 注册页面。
- 音频收藏、历史和设置主要保存在 `PreferenceService`；当前 App 尚未使用 `RelationalStore`。
- `ReadingStatsPage` 和 `StatsService` 当前使用 `listenSeconds` 表达听书统计，不能直接混入阅读时长。
- 系统备份只包含 `files/backup/listenbook_state.json`，并主动排除本地导入内容。
- App 使用 ArkUI V2 和 API 26，新增代码只能使用 `@ComponentV2`、`@Local`、`@Param`、`@Event` 等 V2 装饰器。
- 新增 UI 文案必须放在资源文件中，不能直接在 `.ets` 页面硬编码。

## 3. 总体架构

### 3.1 模块边界

```text
pages/
  ImportPage.ets              统一选择入口，音频和 EPUB 分流
  FavoritePage.ets            聚合书架与类型筛选
  EBookDetailPage.ets         电子书详情、目录入口、删除
  ReaderPage.ets              ReaderKit 组件与阅读交互
  ReadingStatsPage.ets        听书/阅读统计切换

model/
  EBook.ets                   电子书持久化模型
  ReadingPosition.ets         ReaderKit 位置模型
  EBookBookmark.ets           电子书书签模型
  ShelfItem.ets               仅用于书架展示聚合

service/ebook/
  EBookDatabase.ets           RDB 初始化、版本升级和事务
  EBookRepository.ets         表级查询和写入
  EBookImportService.ets      文件校验、复制、解析和去重
  EBookService.ets            查询、删除和业务编排
  ReadingProgressService.ets  进度读取、合并和写入
  BookmarkService.ets         书签增删查
  ReadingStatsService.ets     阅读计时和按日聚合
```

不新增 `viewmodel/`，页面继续使用 `@Local` 状态和 Service 单例。`EBookRepository` 只负责数据访问，跨文件与数据库的操作由 `EBookImportService` 或 `EBookService` 编排。

### 3.2 内容模型分离

不得给现有音频 `Book` 填充 EPUB 路径，也不得使用音频 `Chapter.source` 存正文位置。

书架展示使用明确的 `ShelfItem` 类适配两种内容：

```text
ShelfItem
  stableKey       audio:<bookId> / ebook:<ebookId>
  kind            AUDIO / EBOOK
  id
  title
  author
  cover
  progressLabel
  updatedAt
  audioBook?      仅 AUDIO 有值
  ebook?          仅 EBOOK 有值
```

`stableKey` 必须包含内容类型，避免音频和电子书 ID 碰撞。长列表继续使用 `LazyForEach` 和稳定 key，不使用数组下标。

### 3.3 页面与路由

新增路由：

```text
ebookDetail -> EBookDetailPage
reader      -> ReaderPage
```

新增显式路由参数类：

```text
EBookDetailRouteParams
  bookId

ReaderRouteParams
  bookId
  targetResourceIndex = -1
  targetDomPos = ''
```

默认继续阅读时只传 `bookId`，由 `ReaderPage` 从 `ReadingProgressService` 读取权威进度。只有目录或书签跳转才携带目标位置。路由不传 EPUB 内容、完整目录、Parser 或 Controller 对象。

### 3.4 本地文件结构

```text
files/
  ebooks/
    <bookId>/
      book.epub
      cover.<ext>
    .staging/
      <importSessionId>/
        book.epub
    .trash/
      <deleteSessionId>/
        book.epub
        cover.<ext>
```

规则：

- `bookId` 使用应用生成的 UUID，不使用原始文件名。
- 原始文件名只用于导入预览，不参与路径拼接。
- EPUB 必须先复制到 `.staging`，不得直接在目标目录写入。
- ReaderKit 返回的封面路径不能直接长期持久化；需要复制为电子书目录中的独立封面文件。
- App 启动后清理超过 24 小时且无活动任务的 `.staging` 和 `.trash` 目录。
- 所有清理方法必须可重复调用，文件不存在时视为清理完成。

## 4. ReaderKit 技术契约

### 4.1 已确认的 API 26 能力

本机 HarmonyOS 26.0.0.32 Beta2 SDK 已包含 `@kit.ReaderKit`，关键接口如下：

```text
bookParser.getDefaultHandler(path)
BookParserHandler.getBookInfo()
BookParserHandler.getCatalogList()
BookParserHandler.getSpineList()
BookParserHandler.getDomPosByCatalogHref(href)

ReaderComponentController.init(context)
ReaderComponentController.registerBookParser(handler)
ReaderComponentController.setPageConfig(setting)
ReaderComponentController.startPlay(resourceIndex, domPos)
ReaderComponentController.flipPage(isNext)
ReaderComponentController.on/off('pageShow', callback)
ReaderComponentController.releaseBook()
```

ReaderKit 从版本 5.0.4(16) 提供，目标手机 syscap 中包含 `BookParser` 和 `ReaderCore`。这只能证明编译期和设备类型声明可用，不能替代签名设备上的真机验证。

### 4.2 真实字段映射

ReaderKit 的 `pageShow` 回调返回 `PageDataInfo`：

| ReaderKit 字段 | App 字段 | 用途 |
|---|---|---|
| `resourceIndex` | `ReadingPosition.resourceIndex` | 权威章节/Spine 位置 |
| `startDomPos` | `ReadingPosition.domPos` | 权威页首 DOM 位置 |
| `endDomPos` | 不持久化 | 当前页范围和书签摘要辅助 |
| `pageOffset` | `ReadingPosition.pageOffset` | 同一资源内显示和兜底 |
| `pageHeaderContent` | 当前章节显示 | 非权威位置 |
| `pageFooterContent` | 页脚显示 | 非权威位置 |

计划旧字段 `spineIndex` 统一改名为 `resourceIndex`，避免实现代码和 SDK 名称来回转换。

ReaderKit 不直接提供可信的全书阅读百分比。`percent` 只能作为派生显示值：

- 能获取当前资源总分页信息时，按资源位置和页内位置计算近似百分比。
- 无法获取分母时，书架显示“第 N 章 / 共 M 章”，不伪造精确百分比。
- 任何情况下都只用 `resourceIndex + domPos` 恢复阅读。

### 4.3 初始化与释放顺序

```text
ReaderPage 出现
  -> 查询 EBook 和恢复位置
  -> bookParser.getDefaultHandler(filePath)
  -> 获取 BookInfo / Catalog / Spine
  -> Controller.init(context)
  -> Controller.registerBookParser(handler)
  -> 注册 pageShow / resourceRequest 回调
  -> Controller.setPageConfig(setting)
  -> Controller.startPlay(resourceIndex, domPos)

ReaderPage 消失
  -> 强制刷新最后一次进度和阅读时长
  -> off(pageShow)
  -> off(resourceRequest)
  -> releaseBook()
  -> 清空页面持有的 Handler / Controller 引用
```

进度回调需要串行合并写入：普通 `pageShow` 最多每秒落库一次，页面退出或应用进入后台时立即强制写入。字号、主题或窗口变化触发重新排版时，不得用旧 `pageOffset` 覆盖新的 `domPos`。

### 4.4 阶段 0 必测项

- `ReadPageComponent` 能嵌入 ArkUI V2 页面并通过 `arkts_check` 和构建。
- 当前应用签名调用 `Controller.init()` 不出现 `1016910004 Invalid caller`。
- 沙箱 EPUB 能通过 `getDefaultHandler()` 解析。
- 中文可重排 EPUB 的标题、作者、封面、目录和正文正确。
- 无封面、无作者、目录层级较深的 EPUB 可以降级展示。
- 固定布局 EPUB 至少不会崩溃；若阅读体验不可控，首版明确提示暂不支持。
- 目录 href 能转换为 `resourceIndex + domPos` 并完成跳转。
- 左右翻页和 ReaderKit 原生手势不会重复触发。
- `pageShow` 返回的位置可在杀进程后恢复。
- 切换字号、横竖屏和小窗口后不白屏、不丢失当前位置。
- 反复进入退出 20 次后无回调重复、明显内存增长或 Controller 泄漏。

阶段 0 失败时停止后续实现，不使用 WebView 自研 EPUB 排版器作为临时替代方案。

## 5. 数据模型与数据库

### 5.1 ArkTS 模型

所有模型使用显式 `class`，不使用无类型对象字面量作为跨层数据载体。

```text
EBook
  id: string
  title: string
  author: string
  coverPath: string
  filePath: string
  format: string
  fileSize: number
  checksum: string
  chapterCount: number
  lastReadAt: number
  createdAt: number
  updatedAt: number

ReadingPosition
  bookId: string
  resourceIndex: number
  domPos: string
  pageOffset: number
  percent: number
  updatedAt: number

EBookBookmark
  id: string
  bookId: string
  resourceIndex: number
  domPos: string
  title: string
  snippet: string
  createdAt: number

ReadingDailyStat
  bookId: string
  day: string
  readSeconds: number
  updatedAt: number
```

书签 `snippet` 首版允许为空。只有 ReaderKit 能稳定提供当前页文本或能从对应 Spine 安全提取正文时才生成摘要，不为了摘要引入第二套 HTML 解析流程。

### 5.2 RDB v1 表结构

数据库文件：`ebook_library.db`

```sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS ebooks (
  id TEXT PRIMARY KEY NOT NULL,
  title TEXT NOT NULL,
  author TEXT NOT NULL DEFAULT '',
  cover_path TEXT NOT NULL DEFAULT '',
  file_path TEXT NOT NULL UNIQUE,
  format TEXT NOT NULL DEFAULT 'epub',
  file_size INTEGER NOT NULL DEFAULT 0,
  checksum TEXT NOT NULL UNIQUE,
  chapter_count INTEGER NOT NULL DEFAULT 0,
  last_read_at INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS reading_progress (
  book_id TEXT PRIMARY KEY NOT NULL,
  resource_index INTEGER NOT NULL DEFAULT 0,
  dom_pos TEXT NOT NULL DEFAULT '',
  page_offset INTEGER NOT NULL DEFAULT 0,
  percent REAL NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY(book_id) REFERENCES ebooks(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS bookmarks (
  id TEXT PRIMARY KEY NOT NULL,
  book_id TEXT NOT NULL,
  resource_index INTEGER NOT NULL,
  dom_pos TEXT NOT NULL,
  title TEXT NOT NULL DEFAULT '',
  snippet TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  FOREIGN KEY(book_id) REFERENCES ebooks(id) ON DELETE CASCADE,
  UNIQUE(book_id, resource_index, dom_pos)
);

CREATE INDEX IF NOT EXISTS idx_bookmarks_book_created
  ON bookmarks(book_id, created_at DESC);

CREATE TABLE IF NOT EXISTS reading_daily_stats (
  book_id TEXT NOT NULL,
  day TEXT NOT NULL,
  read_seconds INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY(book_id, day),
  FOREIGN KEY(book_id) REFERENCES ebooks(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_ebooks_last_read
  ON ebooks(last_read_at DESC);
```

数据库版本从 `1` 开始。`EBookDatabase` 必须提供显式 `onCreate`、`onUpgrade` 和事务方法；后续增加字段只能升级版本，不能在页面启动时散落执行临时 SQL。

### 5.3 阅读设置

以下全局阅读设置继续存入 `PreferenceService`，不放入每本书的 RDB：

```text
reader_font_name
reader_font_size
reader_font_weight
reader_line_height
reader_theme
reader_follow_system
reader_flip_mode
```

所有数值读取后必须限制到产品允许范围。ReaderKit 不接受的字体或配置值回退到默认设置，不能阻止打开书籍。

## 6. 服务接口与职责

### 6.1 导入分类

```text
ImportKind
  AUDIO
  AUDIO_ZIP
  EPUB
  MIXED
  UNSUPPORTED
```

分类规则：

- 单个 `.epub` 返回 `EPUB`。
- 多个 EPUB 提示“一次只能导入一本电子书”。
- EPUB 与音频或 ZIP 混选返回 `MIXED`，不进入任何导入流程。
- `.epub` 即使内部是 ZIP，也不能进入现有 `zlib.decompressFile()` 音频分支。
- 扩展名判断后仍要由 ReaderKit 验证实际文件格式。

### 6.2 服务契约

```text
EBookImportService
  classify(files): ImportKind
  inspectEpub(uri): Promise<EBookImportSession>
  commitImport(sessionId, editedTitle): Promise<EBookImportResult>
  cancelImport(sessionId): Promise<void>

EBookService
  getBooks(): Promise<EBook[]>
  getBook(bookId): Promise<EBook | null>
  getBooksWithProgress(): Promise<EBookShelfRecord[]>
  deleteBook(bookId): Promise<void>
  reconcileStorage(): Promise<void>

ReadingProgressService
  get(bookId): Promise<ReadingPosition | null>
  queueSave(position): void
  flush(bookId): Promise<void>
  clear(bookId): Promise<void>

BookmarkService
  list(bookId): Promise<EBookBookmark[]>
  addCurrentPage(bookmark): Promise<BookmarkAddResult>
  remove(bookmarkId): Promise<void>

ReadingStatsService
  beginSession(bookId): void
  pauseSession(): Promise<void>
  endSession(): Promise<void>
  getBookStats(): Promise<ReadingBookStats[]>
  getSummary(): Promise<ReadingStatsSummary>
```

约束：

- Service 使用当前项目已有的单例或静态服务风格，不引入依赖注入框架。
- 页面不直接执行 SQL，也不直接删除 EPUB 目录。
- `EBookRepository` 的写操作必须通过 `EBookDatabase` 的串行队列或事务执行。
- `EBookService.deleteBook()` 是唯一完整删除入口，不再设置第二个含义相近的 `deleteEpub()`。
- `EBookImportSession` 保存 `sessionId`、暂存文件路径和解析预览；页面只持有 `sessionId`，预览和提交不得重复复制 EPUB。

### 6.3 导入事务与崩溃恢复

```text
1. 校验选择结果、扩展名和可预读的文件大小
2. 复制到 .staging/<sessionId>/book.epub，并在复制过程中执行大小上限检查
3. 计算 SHA-256
4. 查询 checksum，命中则返回已有书籍
5. ReaderKit 解析元数据、目录和封面
6. 生成 bookId 和最终目录
7. 把 EPUB 与封面移动到最终目录
8. 在 RDB 事务中插入 ebooks
9. 提交成功后删除 staging
10. 通知书架刷新并进入电子书详情
```

失败策略：

- 第 7 步前失败：删除 staging，不写数据库。
- 第 7 步后、第 8 步失败：删除最终目录，不产生可见记录。
- App 在文件移动后、数据库提交前崩溃：下次启动由 `reconcileStorage()` 删除无数据库引用的孤立目录。
- 重复导入：不复制第二份文件，提示“这本书已在书架中”并打开已有详情页。
- 首版 EPUB 文件上限设为 500 MB；文件大小可预读时在复制前终止，无法预读时在复制过程中达到上限即终止。
- 空间不足、文件不可读和格式损坏必须映射为用户可理解的资源文案。

### 6.4 完整删除事务

```text
1. 查询 EBook，确认最终目录
2. 把最终目录移动到 .trash/<sessionId>
3. RDB 事务删除 ebooks
4. 外键级联删除 progress / bookmarks / daily stats
5. 提交后删除 trash 目录
```

数据库删除失败时尝试把目录移回原位置。App 异常退出后，`reconcileStorage()` 根据数据库记录恢复或清理 `.trash`。删除操作必须防重复点击，并在成功后才从书架列表移除。

首版电子书不提供“仅移出书架但保留文件”，因为当前没有独立的本地电子书文件库入口，保留不可访问的数据会形成孤立文件。确认按钮统一表达为“删除电子书”。

## 7. 页面与交互设计

### 7.1 设计方向

关键词：安静、正文优先、清晰层级、长时间使用不疲劳。

视觉体系继续使用项目现有 `Theme.ets`、系统语义色和 HarmonyOS 7 沉浸材质。电子书功能不引入另一套品牌色，不把页面做成独立的仿纸应用。

唯一新增的领域识别元素是“页签式阅读刻度”：电子书封面右侧可显示一条细窄阅读刻度，表达当前位置；听书继续使用现有章节进度文字。刻度只服务进度识别，不增加阴影、渐变或装饰动画。

### 7.2 书架

保留当前书架的网格/列表切换、拖动删除和顶部导航结构，在标题栏下增加一个横向沉浸筛选控件：

```text
┌ 书架                         [网格/列表] ┐
│ [全部]          [听书]          [电子书] │
├─────────────────────────────────────────┤
│ 当前网格或列表内容                         │
│ [封面] [封面] [封面]                      │
│ 书名   书名   书名                        │
└─────────────────────────────────────────┘
```

规则：

- 筛选控件使用一个 `AppMaterial.InteractiveThin` 容器，不创建三个独立圆角按钮。
- 当前 `HomeTheme` 背景和网格/列表布局保持不变，不在电子书升级中重做书架背景。
- “全部”按最近活动时间聚合排序；没有活动时间时按加入书架时间排序。
- 音频卡片继续显示集数进度和“有声书”类型。
- 电子书卡片显示“电子书”类型、章节位置或可靠的近似百分比。
- 电子书的稳定 key 使用 `ebook:<id>`。
- “电子书”筛选下的添加项显示“导入 EPUB”，点击进入 `ImportPage`。
- “听书”筛选下的添加项保留“去书城寻好书”。
- “全部”筛选下提供导入入口和书城入口，但不能放成嵌套卡片。
- 电子书筛选下禁用下拉刷新；全部筛选下拉刷新时只刷新在线音频书。
- 拖动电子书到删除区后显示电子书专用确认文案，不调用 `DownloadService`。

### 7.3 统一导入页

`ImportPage` 保留统一入口，但选择文件后立即分流：

```text
选择文件
  ├─ 单个 .epub        -> EPUB 预览
  ├─ 音频 / 音频 ZIP   -> 现有音频导入预览
  ├─ 多个 .epub        -> 提示一次导入一本
  ├─ EPUB + 音频       -> 提示不能混合导入
  └─ 其他格式           -> 提示暂不支持
```

EPUB 预览显示封面、书名、作者、文件大小和目录章数。书名允许修改，作者首版只读 ReaderKit 元数据；没有作者时显示资源文案“未知作者”。预览和提交复用同一个 `EBookImportSession`，用户取消时调用 `cancelImport(sessionId)`。

解析期间使用显式设置 `.color(AppColor.Brand)` 的 `LoadingProgress`。用户离开页面时取消尚未开始提交的导入任务并清理 staging；文件已进入提交阶段时禁用重复返回和重复提交。

### 7.4 电子书详情页

```text
┌ [返回]                              [更多] ┐
│              [封面]                         │
│              书名                           │
│              作者 · EPUB                    │
│              第 3 章 / 共 20 章             │
│                                             │
│              [继续阅读]                     │
├─────────────────────────────────────────────┤
│ 目录                                      > │
│ 书签                                      > │
│ 文件信息                                  > │
└─────────────────────────────────────────────┘
```

- 主按钮根据进度显示“开始阅读”或“继续阅读”。
- 页面不显示音频专用章节播放控件和迷你播放器。
- 目录和书签使用 Sheet 展示，目录支持层级缩进和当前位置标识。
- 更多菜单包含“删除电子书”，删除前显示文件和阅读数据都会被清理。
- 文件信息显示格式、文件大小和导入日期，不展示沙箱绝对路径。
- 封面缺失时使用现有应用的文本占位样式，不生成装饰性假封面。

### 7.5 阅读页

```text
┌ [返回] 书名                         [书签] ┐
│                                             │
│                                             │
│               ReaderKit 正文                │
│                                             │
│                                             │
├─────────────────────────────────────────────┤
│ [目录]       第 3 章 / 共 20 章       [设置] │
└─────────────────────────────────────────────┘
```

- 正文是第一视觉主体，进入页面后顶部和底部工具栏默认隐藏。
- 点击正文中央区域切换工具栏；左右区域翻页。
- 系统返回手势、顶部返回按钮和页面销毁走同一进度刷新与释放逻辑。
- 工具栏出现和消失使用 `AppMotion.Fast` 或 `AppMotion.Base`，不使用持续动画。
- 工具栏使用 `AppMaterial.InteractiveClean`，设置和目录 Sheet 使用 `AppMaterial.SurfaceRegular`。
- 顶部按钮使用系统 SymbolGlyph，并提供可访问性描述和至少 44vp 点击区域。
- 阅读背景使用离散主题资源；正文页不使用渐变背景、装饰光球或额外卡片。
- 工具栏、正文和 Sheet 必须避让状态栏、导航区域和小窗口安全区。
- 窗口尺寸变化时先保存当前 DOM 位置，再更新 `ReaderSetting.viewPortWidth/viewPortHeight` 并重新排版。

阅读设置控件：

| 设置 | 控件 | 规则 |
|---|---|---|
| 字号 | 减号/加号步进器 | 显示当前字号，限制最小和最大值 |
| 字体 | 菜单 | 只列出已验证可用字体 |
| 行距 | 三段式选择 | 紧凑、标准、宽松 |
| 主题 | 颜色 swatch | 使用资源色，显示选中状态 |
| 跟随系统 | Switch | 开启后禁用手动深浅模式冲突项 |
| 翻页方式 | 分段控件 | 只展示 ReaderKit 真机验证通过的模式 |

### 7.6 记录页

现有页面名称和底部 Tab“记录”保持不变，页面内部增加“收听 / 阅读”切换：

- 收听视图继续使用现有 `StatsService` 和 `listenSeconds`。
- 阅读视图使用 `ReadingStatsService` 和 `readSeconds`。
- 两种统计不得合并成一个含义模糊的总时长。
- 阅读历史按 `ebooks.last_read_at` 倒序展示。
- 删除阅读历史只清理统计，不删除电子书和阅读进度；文案必须明确。

## 8. 页面、接口与数据表映射

本功能没有服务端 HTTP API，以下“接口”均为 App 内的强类型 Service API。

| 页面/流程 | 主要接口 | 数据表/文件 | 失败处理 |
|---|---|---|---|
| `ImportPage` 文件分类 | `EBookImportService.classify()` | 无 | 混选或多 EPUB 直接拦截 |
| `ImportPage` EPUB 预览 | `inspectEpub()` | `.staging` 临时文件 | 退出或解析失败清理临时文件 |
| `ImportPage` 提交 | `commitImport()` | `ebooks`、EPUB、封面 | 文件与数据库补偿回滚 |
| `FavoritePage` 聚合 | `DataService` + `EBookService.getBooksWithProgress()` | 音频 Preferences/JSON + `ebooks`、`reading_progress` | 单类加载失败不阻断另一类展示 |
| `EBookDetailPage` | `getBook()`、`get()`、`list()` | `ebooks`、`reading_progress`、`bookmarks` | 文件缺失时提示重新导入或删除记录 |
| `ReaderPage` 初始化 | ReaderKit + `ReadingProgressService.get()` | EPUB、`reading_progress` | 位置无效时逐级回退 |
| `ReaderPage` 翻页 | `queueSave()` | `reading_progress` | 内存合并，退出时强制刷新 |
| `ReaderPage` 书签 | `BookmarkService` | `bookmarks` | 同位置重复书签返回已有记录 |
| `ReaderPage` 计时 | `ReadingStatsService` | `reading_daily_stats`、`ebooks.last_read_at` | 后台、锁屏和离开页面停止计时 |
| `EBookDetailPage` 删除 | `EBookService.deleteBook()` | 四张表、EPUB、封面 | trash + RDB 事务补偿 |
| `ReadingStatsPage` | `ReadingStatsService` | `reading_daily_stats`、`ebooks` | 空状态不影响收听统计 |

## 9. 状态、生命周期与异常

### 9.1 进度恢复优先级

```text
显式目录/书签目标
  -> reading_progress.resourceIndex + domPos
  -> resourceIndex + 空 domPos
  -> 第一个有效 Spine + 空 domPos
  -> 显示无法打开提示
```

当 ReaderKit 抛出位置越界或 DOM 失效错误时，只降级一次，避免重试死循环。降级成功后使用新的 `pageShow` 位置覆盖旧进度。

### 9.2 阅读计时

只有同时满足以下条件才累计阅读时长：

- `ReaderPage` 位于前台且可见
- EPUB 已成功开始显示正文
- App 和当前窗口处于活动状态

单次连续计时每 30 秒写入内存累计值，页面离开、应用后台或每满 60 秒落库。异常退出最多损失 60 秒，不通过高频数据库写入换取秒级精度。

### 9.3 常见错误与用户动作

| 场景 | 页面提示 | 用户动作 |
|---|---|---|
| 文件损坏或不是有效 EPUB | 无法读取这本电子书 | 重新选择文件 |
| ReaderKit 调用方无效 | 当前设备暂时无法使用阅读功能 | 返回书架 |
| 文件超过 500 MB | 文件过大，暂不支持导入 | 选择较小文件 |
| 空间不足 | 存储空间不足，无法完成导入 | 清理空间后重试 |
| 重复导入 | 这本书已在书架中 | 打开已有书籍 |
| EPUB 文件被异常移除 | 本地文件缺失 | 删除记录或重新导入 |
| 保存进度失败 | 不阻断翻页 | 页面退出时重试并记录日志 |
| 删除失败 | 未能删除电子书 | 保持书架记录并允许重试 |

所有文案进入资源文件。日志只记录错误码、步骤和内部 bookId，不打印正文、书签摘要、完整文件路径或用户原始文件名。

## 10. 备份、迁移与兼容

### 10.1 首版备份策略

- EPUB、封面、`ebook_library.db` 不加入系统备份白名单。
- `PreferenceBackupSnapshot` 不加入电子书 ID、进度或书签。
- 通用阅读设置可以进入设置备份，但恢复后没有电子书时不产生书架记录。
- 首版不实现跨设备继续阅读。

### 10.2 旧数据处理

- 不把旧 `contentType = text` 的音频 `Book` 自动迁移为 `EBook`。
- 旧文本收藏继续按现有逻辑过滤。
- 新电子书 ID 使用独立命名空间，不以 `search_text_` 或 `home_text_` 开头。
- 卸载重装后本地 EPUB 和电子书数据库一起消失，行为保持一致。

### 10.3 数据库升级

- RDB v1 首次创建四张表和索引。
- 每次升级在一个事务内完成，并更新数据库版本。
- 升级失败不得删除旧数据库；记录错误并暂时隐藏电子书入口。
- 开发阶段需要保留至少一份 v1 测试数据库，用于后续版本迁移回归。

## 11. 分阶段实施

### 阶段 0：ReaderKit 技术验证

交付物：

- 独立最小验证页或临时验证分支
- 一份合法 EPUB 和一份损坏 EPUB 测试样本
- 编译、真机日志和生命周期结论
- 字段映射与已验证 `flipMode` 清单

完成门槛：合法 EPUB 能打开、翻页、目录跳转，杀进程后按 DOM 位置恢复；连续进出页面无崩溃和明显泄漏。

### 阶段 1：数据层和文件基础设施

交付物：

- `EBook`、`ReadingPosition`、`EBookBookmark`、`ShelfItem` 类
- `EBookDatabase` 和 RDB v1
- Repository、事务队列和 storage reconcile
- SHA-256、staging、trash 和幂等清理
- 数据层单元测试

完成门槛：可以通过测试创建、查询、更新、级联删除电子书数据，并模拟导入/删除中断后的恢复。

### 阶段 2：统一导入

交付物：

- `.epub` 文件筛选
- 音频、ZIP、EPUB 和混选分类
- EPUB 元数据预览
- 原子导入、重复检测和错误提示
- 导入完成后进入电子书详情

完成门槛：合法、重复、损坏、超限、空间不足和取消六类场景行为明确，现有音频导入回归通过。

### 阶段 3：书架和详情

交付物：

- 统一 `ShelfItem` 数据源
- 全部/听书/电子书筛选
- 网格/列表两种电子书卡片
- `EBookDetailPage`、目录和删除
- 新增路由与强类型参数类

完成门槛：两类内容可稳定筛选、排序、打开和删除；音频刷新、拖动删除和播放入口无回归。

### 阶段 4：阅读核心

交付物：

- `ReaderPage` 和 ReaderKit 生命周期
- 翻页热区、目录跳转、工具栏显隐
- 进度保存、杀进程恢复和位置回退
- 字号、字体、行距、主题和翻页方式
- 深浅主题、小窗口和安全区适配

完成门槛：正文稳定显示，20 次进入退出无白屏和重复回调，配置变化后位置恢复正确。

### 阶段 5：书签与统计

交付物：

- 当前页书签、书签列表和跳转
- 按日阅读时长
- 记录页“收听 / 阅读”切换
- 阅读历史删除与空状态

完成门槛：书签定位稳定，前后台计时不重复，阅读统计和听书统计互不污染。

### 阶段 6：回归和发布准备

交付物：

- `arkts_check`、增量构建和真机启动验证
- 导入、书架、详情、阅读、恢复、删除全链路报告
- 音频搜索、详情、章节、播放、下载和本地导入回归
- 深浅主题、小窗口、系统安全区和无障碍检查
- 数据库 v1 和清理策略说明

完成门槛：本计划验收清单全部通过，没有阻断级缺陷。

## 12. 测试方案

### 12.1 单元测试

新增建议：

```text
EBookImportClassifier.test.ets
EBookImportPolicy.test.ets
ReadingPositionPolicy.test.ets
EBookStorageReconcile.test.ets
ReadingStatsPolicy.test.ets
```

覆盖：

- 文件扩展名和混选分类
- 500 MB 边界
- checksum 重复策略
- ReaderKit 字段到 `ReadingPosition` 的转换
- DOM 位置回退顺序
- staging/trash 孤立目录处理
- 级联删除和幂等删除
- 前后台阅读计时和跨日统计

RDB 和真实文件 API 无法在本地单测稳定运行的部分放入设备测试，不通过大量 mock 掩盖平台行为。

### 12.2 设备测试

- 首次创建数据库和重复初始化
- 导入后 EPUB、封面和数据库路径一致
- 删除后四张表和目录均无残留
- 杀进程恢复、窗口变化恢复和无效 DOM 回退
- App 后台、锁屏、返回前台后的计时
- ReaderKit 错误码映射

### 12.3 EPUB 样本矩阵

至少准备：

- 中文可重排 EPUB，带封面和多级目录
- 无封面、无作者 EPUB
- 大量章节 EPUB
- 图片较多 EPUB
- 固定布局 EPUB
- 文件名含中文和空格的 EPUB
- 扩展名为 `.epub` 但内容损坏的文件
- 内容相同但文件名不同的重复文件

测试 EPUB 不提交包含版权内容的完整商业书籍；仓库样本使用自制或公版内容。

### 12.4 必须执行的工程检查

1. 对所有新增和修改的 `.ets` 文件执行 `arkts_check`。
2. ArkTS 报错时先按 `arkts-error-fixes` 处理，再重新检查。
3. 使用 `build_project` 增量构建；只有怀疑缓存损坏时才 clean。
4. 构建成功后使用 `start_app` 在 API 26 真机启动。
5. 修改导入、书架或阅读统计后，同时执行对应音频回归。

## 13. 验收清单

### 导入与数据

- [ ] 音频和音频 ZIP 导入行为没有改变。
- [ ] 单个 EPUB 能导入并生成书名、作者、封面和目录。
- [ ] 多 EPUB、混选、损坏、超限和空间不足均被正确处理。
- [ ] 相同内容重复导入不会产生第二份文件或记录。
- [ ] 导入取消或失败后 staging、最终目录和数据库没有半成品。
- [ ] 新增数据库具备版本、事务、外键和必要索引。

### 书架与详情

- [ ] 全部/听书/电子书筛选与网格/列表切换可以组合使用。
- [ ] 电子书和音频使用不同稳定 key，不发生节点错误复用。
- [ ] 电子书卡片显示类型和可靠的阅读位置。
- [ ] 全部模式只刷新在线音频，电子书模式不触发无效刷新。
- [ ] 详情页目录、书签、文件信息和继续阅读入口正常。
- [ ] 删除后 EPUB、封面、进度、书签和统计没有残留。

### 阅读

- [ ] 阅读页正文优先，工具栏默认隐藏。
- [ ] 目录跳转、左右热区和 ReaderKit 原生手势正常。
- [ ] 字号、字体、行距、主题和翻页方式可保存。
- [ ] 杀进程后按 `resourceIndex + domPos` 恢复。
- [ ] 字号、主题和窗口尺寸变化后不依赖旧页码。
- [ ] 无效 DOM 能降级到资源开头，不产生循环崩溃。
- [ ] 页面退出时注销回调并调用 `releaseBook()`。
- [ ] 连续进入退出 20 次无白屏、重复回调和明显泄漏。

### 统计与体验

- [ ] 阅读时长只在正文可见且 App 前台时累计。
- [ ] 收听和阅读统计分开呈现、分开删除。
- [ ] 工具栏、Sheet、正文和系统安全区不重叠。
- [ ] 所有 LoadingProgress 显式使用 `AppColor.Brand`。
- [ ] 所有新增文案来自资源文件。
- [ ] 深色模式、小窗口和系统字体放大场景可用。
- [ ] 系统备份不会恢复出缺少 EPUB 的孤立电子书。

### 工程回归

- [ ] 通过 `arkts_check`。
- [ ] 通过 `build_project` 增量构建。
- [ ] 通过 `start_app` 真机启动和完整链路验证。
- [ ] 音频搜索 -> 详情 -> 章节 -> 播放无回归。
- [ ] 音频下载、导出、本地导入和书架刷新无回归。

## 14. 风险与停止条件

| 风险 | 影响 | 控制措施 | 停止条件 |
|---|---|---|---|
| ReaderKit 与 ArkUI V2 组合不稳定 | 阅读页无法发布 | 阶段 0 最小验证 | 真机持续白屏或生命周期崩溃 |
| ReaderKit 调用方校验失败 | 无法初始化 | 使用当前签名和发布签名分别验证 | 合法签名仍返回 Invalid caller |
| DOM 位置跨排版不稳定 | 无法可靠续读 | 多字体、多窗口恢复测试 | 杀进程恢复无法达到章节内位置 |
| RDB 和文件系统不一致 | 孤立文件或坏记录 | staging、trash、事务和 reconcile | 无法实现幂等恢复 |
| 书架聚合破坏音频流程 | 核心功能回归 | 类型适配层和音频全链路测试 | 音频播放/收藏出现阻断回归 |
| 固定布局 EPUB 兼容性差 | 部分书籍不可读 | 阶段 0 明确支持边界 | 正文不可用且无法识别类型 |

任何停止条件命中后，不进入下一阶段，也不通过引入客户端 WebView 排版器、Legado 规则引擎或服务端正文解析扩大首版范围。

## 15. 后续候选能力

以下内容等本地 EPUB 阅读稳定后单独评估：

- PDFKit 阅读页
- TXT 和 MOBI 导入
- 全文搜索
- 划线、批注和笔记
- TTS 朗读和音画同步
- EPUB 与进度备份
- 跨设备继续阅读
- 服务端电子书接口

每项后续能力必须单独定义数据升级和隐私边界，不能直接追加到首版 RDB 字段中。

## 16. 相关工程参考

- `entry/src/main/ets/pages/ImportPage.ets`
- `entry/src/main/ets/pages/FavoritePage.ets`
- `entry/src/main/ets/pages/Index.ets`
- `entry/src/main/ets/pages/ReadingStatsPage.ets`
- `entry/src/main/ets/service/DataService.ets`
- `entry/src/main/ets/service/PreferenceService.ets`
- `entry/src/main/ets/service/StatsService.ets`
- `entry/src/main/ets/service/AppBackupService.ets`
- `entry/src/main/ets/theme/Theme.ets`
- `entry/src/main/resources/base/profile/backup_config.json`
- `docs/APP_UI.md`
- `CLAUDE.md`
