# 本地电子书阅读功能计划

状态：方案评估中，暂不修改业务代码。

## 1. 目标与范围

在现有 ListenBook 音频 App 中增加本地电子书能力，第一阶段只支持 EPUB 文件。导入入口复用现有 `ImportPage`，但电子书和音频在导入、存储、详情、阅读和进度逻辑上分开。

第一阶段目标链路：

```text
系统文件选择器
  -> ImportPage 判断文件类型
  -> 复制 EPUB 到应用沙箱
  -> ReaderKit 读取元数据和目录
  -> 加入书架
  -> EBookDetailPage
  -> ReaderPage 阅读、翻页、恢复进度
```

第一阶段包含：

- 单个 EPUB 导入
- 自动读取书名、作者、封面和目录
- 书架中的电子书筛选
- 开始阅读、继续阅读
- 目录跳转和左右翻页
- 字号、字体、行距、阅读主题、夜间模式
- 阅读位置保存
- 当前页书签
- 删除电子书及其本地数据

第一阶段不包含：

- 在线电子书源、服务端接口和云同步
- PDF、TXT、MOBI、AZW3 等其他格式
- 划线、批注、想法和社交功能
- 全文搜索
- TTS 朗读和音画同步
- DRM 加密电子书

## 2. 当前工程约束

- 当前 `Book` 和 `Chapter` 以音频为中心，电子书不复用音频章节模型。
- 现有 `ImportPage` 继续作为统一导入入口；音频导入流程保持不变。
- 电子书使用独立 `EBook` 模型和 `EBookService`，书架只在展示层聚合两类内容。
- 页面继续使用 ArkUI V2：`@ComponentV2`、`@Local`、`@Param`。
- 不新增客户端 Legado/阅读规则引擎。
- 目标 SDK 为 HarmonyOS 7 / API 26，ReaderKit 需要先在真机验证。
- 所有新增 `.ets` 文件遵守 ArkTS 严格模式，不使用 `any`、`unknown`、动态属性访问和无类型对象字面量。

## 3. UI 设计方向

### 3.1 设计关键词

安静、内容优先、可长时间阅读、轻量沉浸。

阅读页参考微信读书的交互节奏，但不复制其社交信息流。正文是第一视觉主体，工具栏只在用户操作时出现。

### 3.2 视觉基线

复用 `entry/src/main/ets/theme/Theme.ets` 的既有 token，不在页面中复制颜色值：

| 场景 | 材质/颜色 | 规则 |
|---|---|---|
| 书架顶部筛选 Tab | `AppMaterial.InteractiveThin` | 不设置实色背景，不叠加额外阴影；选中文字和指示线使用 `AppColor.Brand` |
| 导入、开始阅读等主要按钮 | `AppMaterial.SurfaceRegular` | 使用项目品牌软色材质，保持清晰的按下反馈 |
| 顶部返回、书签、更多等图标按钮 | `AppMaterial.FloatingControl` | 使用系统 SymbolGlyph，保留交互光感和可点击区域 |
| 阅读页顶部工具栏 | `AppMaterial.InteractiveClean` | 半透明、无硬边，随正文显隐，不覆盖正文标题区域 |
| 阅读页底部进度和设置栏 | `AppMaterial.InteractiveThin` | 不使用平面色块；进度轨道仍使用主题资源 |
| 目录、阅读设置 Sheet | `AppMaterial.SurfaceRegular` | 使用现有播放器/配置 Sheet 的圆角、阴影和关闭手势 |
| 确认删除对话框 | `AppMaterial.DialogUltraThick` | 危险操作使用 `AppColor` 中已有危险资源或系统语义色 |

所有 Tab 和按钮都必须使用沉浸光感材质。按钮优先使用系统 SymbolGlyph；已有明确图标的操作不再绘制带文字的圆角矩形。纯文字动作只在没有合适图标或需要明确表达时使用。

禁止：

- 页面内硬编码品牌色
- 线性渐变、装饰性光球和额外的卡片套卡片
- 为了“玻璃感”给每个控件增加独立阴影
- 使用系统默认蓝色 LoadingProgress

### 3.3 书架布局

```text
┌ 状态栏沉浸区域 ┐
│ 书架                         [导入] │  <- FloatingControl
│ [全部] [听书] [电子书]              │  <- InteractiveThin
├──────────────────────────────────┤
│ 最近阅读                           │
│ [封面] 书名                       │
│         作者 · 阅读 42%            │
├──────────────────────────────────┤
│ 我的电子书                         │
│ [封面] 书名                       │
│         最后阅读：第 3 章          │
└──────────────────────────────────┘
```

- 当前已有书架继续保留，电子书增加类型标识和阅读进度。
- “全部 / 听书 / 电子书”使用一个横向沉浸材质容器，避免三个孤立色块。
- 长列表使用稳定 key，不能使用数组下标。
- 空状态必须提供明确动作，例如“导入 EPUB”，动作本身使用沉浸材质按钮。

### 3.4 统一导入页

现有 `ImportPage` 增加 EPUB 分支，但不把电子书处理逻辑继续堆进音频方法：

```text
选择文件
  ├─ 单个 .epub       -> 电子书预览信息
  ├─ 音频 / .zip       -> 现有音频导入预览
  ├─ 多个 .epub       -> 提示一次导入一本
  └─ EPUB + 音频      -> 提示不能混合导入
```

EPUB 选中后自动解析书名、作者和封面；用户可以修改标题，但不需要手动填写才能继续。EPUB 不能走现有音频 ZIP 解压分支，即使 EPUB 内部也是 ZIP 结构。

### 3.5 电子书详情页

新增 `EBookDetailPage`，不继续扩展已经音频化的 `BookDetailPage`。

```text
┌ 返回              [书签/更多] ┐
│       [封面]                  │
│       书名                    │
│       作者 · EPUB             │
│       已读 42%                │
│ [继续阅读]                    │  <- SurfaceRegular
├──────────────────────────────┤
│ 目录                     >    │  <- InteractiveThin 行操作
│ 文件信息                      │
└──────────────────────────────┘
```

主按钮根据进度显示“开始阅读”或“继续阅读”。详情页不显示音频迷你播放器控制。

### 3.6 阅读页

```text
┌ [返回] 书名              [书签] ┐  <- InteractiveClean/FloatingControl
│                                │
│                                │
│          ReaderKit 正文         │
│                                │
│                                │
├────────────────────────────────┤
│ [目录]     第 3 章 · 42%   [设置] │ <- InteractiveThin
└────────────────────────────────┘
```

- 默认隐藏顶部和底部工具栏，点击正文中部切换显示状态。
- 顶部返回、书签、更多均为图标按钮并带可访问性描述。
- 左右区域翻页；手势和 ReaderKit `flipPage()` 保持一致。
- 工具栏出现/消失使用 `AppMotion.Fast` 或 `AppMotion.Base`，避免持续动画。
- 字体和主题设置通过 `SurfaceRegular` Sheet 展开，沿用播放器弹层的关闭手势和安全区避让。
- 正文区域不能被工具栏、系统安全区或弹层遮挡。
- 阅读页不放渐变背景；阅读背景使用离散主题资源，主题切换只做短时过渡。

## 4. 页面与路由

新增路由：

```text
ebookDetail -> EBookDetailPage
reader      -> ReaderPage
```

路由参数只传 `bookId` 和可选恢复位置，不传完整 EPUB 内容或完整目录。

页面职责：

| 页面 | 职责 |
|---|---|
| `ImportPage` | 选择文件、类型判断、调用导入服务、展示进度 |
| `FavoritePage` | 聚合音频书和电子书、筛选、删除、打开详情 |
| `EBookDetailPage` | 电子书元数据、进度、目录入口、开始/继续阅读 |
| `ReaderPage` | ReaderKit 生命周期、阅读控制、进度回写 |
| `ReadingStatsPage` | 后续增加阅读时长和阅读历史筛选 |

## 5. 模型与本地数据

新增数据模型：

```text
EBook
  id, title, author, coverPath, filePath, format,
  fileSize, checksum, chapterCount, createdAt, updatedAt

ReadingPosition
  bookId, spineIndex, domPos, pageOffset, percent, updatedAt

Bookmark
  id, bookId, spineIndex, domPos, title, snippet, createdAt
```

本地数据库表：

```sql
ebooks(id PRIMARY KEY, title, author, cover_path, file_path,
       format, file_size, checksum, chapter_count, created_at, updated_at)

reading_progress(book_id PRIMARY KEY, spine_index, dom_pos,
                 page_offset, percent, updated_at)

bookmarks(id PRIMARY KEY, book_id, spine_index, dom_pos,
          title, snippet, created_at)
```

进度恢复以 `spineIndex + domPos` 为权威位置，`pageOffset` 和 `percent` 仅用于显示和兜底。字号、窗口尺寸变化后不能依赖旧页码。

## 6. 服务接口设计

```text
EBookImportService
  classify(files): ImportKind
  importEpub(uri): Promise<EBook>
  deleteEpub(bookId): Promise<void>

EBookService
  getBooks(): Promise<EBook[]>
  getBook(bookId): Promise<EBook | null>
  saveBook(book): Promise<void>
  removeBook(bookId): Promise<void>

ReadingProgressService
  get(bookId): Promise<ReadingPosition | null>
  save(position): Promise<void>
  clear(bookId): Promise<void>

BookmarkService
  list(bookId): Promise<Bookmark[]>
  add(bookmark): Promise<void>
  remove(bookmarkId): Promise<void>
```

ReaderKit 控制器暂时由 `ReaderPage` 持有，避免把 UI 组件控制器强行做成全局单例。页面退出时必须注销回调并调用 `releaseBook()`。

## 7. 分阶段执行

### 阶段 A：ReaderKit 验证

- 验证 `@kit.ReaderKit` 在 ArkUI V2 页面中编译。
- 验证应用沙箱 EPUB 解析、元数据、目录、正文和翻页。
- 验证 `pageShow` 位置回调和重新打开恢复。
- 使用 API 26 真机完成验证。

完成标准：一份 EPUB 能打开、翻页、退出后恢复到原位置。

### 阶段 B：数据层

- 新增 `EBook`、`ReadingPosition`、`Bookmark` 类。
- 初始化 `RelationalStore` 和三张表。
- 完成文件路径、校验值和删除清理。
- 主题、字号、行距使用 `PreferenceService` 持久化。

### 阶段 C：复用导入页

- `.epub` 加入文件筛选器。
- 增加文件分类判断。
- EPUB 和音频流程严格分流。
- 自动读取元数据并写入 `ebooks`。
- 保证原有音频和 ZIP 导入回归通过。

### 阶段 D：书架与详情

- 书架增加“全部 / 听书 / 电子书”沉浸 Tab。
- 统一卡片信息结构，显示类型和进度。
- 增加电子书详情路由。
- 电子书删除同时清理文件、进度和书签。

### 阶段 E：阅读页

- 接入 ReaderKit 控制器和页面组件。
- 完成工具栏显隐、目录、书签、阅读设置。
- 所有 Tab、按钮、图标操作使用沉浸光感材质。
- 工具栏和 Sheet 完成安全区、深浅色和小窗口适配。

### 阶段 F：统计与回归

- 阅读历史和阅读时长接入记录页。
- 评估是否纳入备份；第一版不备份 EPUB 二进制文件。
- 执行 `arkts_check`、`build_project` 和 `start_app`。
- 真机验证导入、阅读、恢复、删除、音频回归和深浅主题。

## 8. 验收清单

- [ ] 音频导入行为没有改变。
- [ ] 单个 EPUB 能导入并自动生成元数据。
- [ ] EPUB 与音频混选会被拦截。
- [ ] 书架 Tab 和按钮均使用沉浸光感材质。
- [ ] 电子书卡片能进入正确详情页。
- [ ] 阅读页正文优先，工具栏默认隐藏。
- [ ] 目录跳转和左右翻页正常。
- [ ] 字号、行距、主题、夜间模式可保存。
- [ ] 杀进程后能恢复到 `spineIndex + domPos`。
- [ ] 删除后本地文件、进度和书签没有残留。
- [ ] 小窗口、深色模式和系统安全区无重叠。
- [ ] 通过 ArkTS 检查、增量构建和真机回归。

## 9. 暂不决策事项

以下内容等本地 EPUB 阅读稳定后再评估：

- 是否增加 PDFKit 阅读页
- 是否支持 TXT 和 MOBI
- 是否实现全文搜索
- 是否实现划线、批注和笔记
- 是否增加 TTS 或音画同步
- 是否增加服务端电子书接口和跨设备同步

## 10. 相关工程参考

- `entry/src/main/ets/pages/ImportPage.ets`
- `entry/src/main/ets/pages/FavoritePage.ets`
- `entry/src/main/ets/pages/Index.ets`
- `entry/src/main/ets/theme/Theme.ets`
- `docs/APP_UI.md`
- `CLAUDE.md`
