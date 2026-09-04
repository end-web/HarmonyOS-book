# ListenBook（简·欢 / 欢FM）

纯血鸿蒙听书 App。当前形态：**手机端 + 单一内置源 + 本地规则源旁路**。欢FM 保持原链路，用户可额外导入 Legado/Reader 书源并执行当前受控兼容子集。

在线内容按以下链路提供：

| 来源类型 | ID / 存储 | 接入方式 |
|---|---|---|
| 内置音频源 | `huan_fm`（欢FM） | App 通过内置加密协议直接接入内容服务 |
| 既有文本源 | `KkBiqugeTextSource` | 由搜索页独立并行搜索，继续复用现有详情和 ReaderKit 阅读链 |
| 本地规则源 | 加密数据库 `rule_sources.db` | 用户从“我的 → 书源”导入；App 旁路执行声明式规则及受限 QuickJS 脚本子集 |

本地导入音频、章节下载离线与文件管理导出、桌面播放卡片、隐私同意与使用说明已落地。TV/Pad 暂不做。

## 技术基线

- HarmonyOS 7 / API 26，`targetSdkVersion = compatibleSdkVersion = 26.0.0`，stage 模式
- 当前本机 SDK 为 `HarmonyOS 26.0.0.32 Beta2`；代码只使用该 SDK 已声明并通过构建的 API 26 能力
- 单 module：`entry/`（type=entry，deviceTypes=phone）
- ArkUI 使用 **V2 装饰器**（`@ComponentV2` / `@Local` / `@Param` / `@Event` / `@ObservedV2` / `@Trace`）
- `bundleName`: `com.huan.listenbook`
- 版本示例：`versionName 0.1.1` / `versionCode 1000001`（以 `AppScope/app.json5` 为准）
- 后台模式：`audioPlayback` + `dataTransfer` + `KEEP_BACKGROUND_RUNNING`
- 网络：`INTERNET`；体感：`VIBRATE`
- 本地书源脚本：`entry/libs/quickjs.har`（arm64-v8a + x86_64），业务层仅通过有界 QuickJS 门面调用
- 签名配置属于本机私有设置，不提交证书路径、Profile 或口令；请在 DevEco Studio 的 Signing Configs 中本地配置

### HarmonyOS 7 SDK 边界

- UI 使用 API 26 `uiMaterial.ImmersiveMaterial` / `systemMaterial`，统一首页悬浮控件、播放器弹层和配置 Sheet。
- `MiniPlayer` 的小圆封面保持静止，外圈使用原生 `ProgressType.Ring` 展示当前集收听进度；完整播放页封面同样不旋转。
- `AVSessionService` 向系统媒体中心声明倍速、上一集、下一集和收藏控件，不在系统卡片显示循环模式；倍速变更与 App 播放状态双向同步。
- 在线音频通过 `MediaSource.enableOfflineCache(true)` 使用系统托管缓存；用户主动下载的完整章节仍由 `DownloadService` 持久化，两者不互相替代。
- Beta2 已接入 `setSupportedPlaySpeeds`、`setSupportedLoopModes` 和 `setMediaCenterControlType`；媒体中心控件优先展示倍速，循环模式仅保留 App 内控制。这些增强能力失败时按单项降级，不阻断 AVSession 激活。
- 普通应用不能通过 `fileAccess` 将整个私有沙箱挂载到文件管理；完整下载仍保存在 `context.filesDir`，用户可在下载管理页通过系统 `DocumentViewPicker` 选择目标位置并导出音频副本。

## 仓库结构

```
ListenBook/
├── entry/                    # 鸿蒙 App 主模块
│   ├── libs/quickjs.har      # 有界 QuickJS 双 ABI 本地依赖
│   └── src/main/ets/         # 业务代码（见下）
├── server/                   # 保留的可选独立后端工程；App 当前不注册或配置它
│   ├── src/                  # API / 聚合 / 书源同步
│   ├── admin/                # 运维后台（Vue 3）
│   └── deploy/               # Docker Compose + Caddy
├── docs/
│   └── APP_UI.md             # 当前页面行为与 UI 回归基线
├── third_party/quickjs/      # QuickJS 模块源码、修改说明与许可证
├── scripts/build-quickjs.ps1 # 重建并同步本地 HAR
├── THIRD_PARTY_NOTICES.md    # 第三方组件声明
├── AppScope/                 # 全局 app 元数据与图标
├── CLAUDE.md                 # 本文件：项目真相源
├── AGENTS.md                 # 协作与工程约定
└── README.md                 # 对外简介
```

### App 目录约定

```
entry/src/main/ets/
├── entryability/             # UIAbility 入口（EntryAbility）
├── entrybackupability/       # 备份扩展（EntryBackupAbility）
├── pages/                    # 路由页面
│   ├── Index.ets             # 根路由 / NavPathStack
│   ├── MainPage.ets          # 四 Tab 主框架（双击当前 Tab 回顶）
│   ├── HomePage.ets          # 首页（固定搜索/分类、骨架屏、下拉刷新、推荐区块）
│   ├── FavoritePage.ets      # 书架
│   ├── ReadingStatsPage.ets  # 听书统计与历史批量管理
│   ├── ProfilePage.ets       # 我的（含同级书源入口）
│   ├── PlayerPage.ets        # 播放器
│   ├── BookDetailPage.ets    # 详情
│   ├── BlockMorePage.ets     # 首页区块「更多」
│   ├── ImportPage.ets        # 本地音频导入
│   ├── RuleSourcePage.ets    # 本地书源导入、测试、启停与删除
│   ├── RuleSourceChildrenPage.ets # 聚合源的只读子源目录
│   ├── RuleSourceLoginPage.ets # HTTPS 内嵌登录与隔离 Cookie 回写
│   ├── DownloadManagerPage.ets
│   ├── SettingsPage.ets / GuidePage.ets / AboutPage.ets / PrivacyPage.ets
├── components/               # MiniPlayer / BookCard 等
├── service/                  # 业务服务（注意：单数）
│   ├── http/                 # HttpClient
│   ├── builtin/              # 内置音频源体系
│   │   ├── BuiltInSourceRegistry.ets
│   │   ├── BuiltInDispatcher.ets
│   │   └── sources/
│   │       └── TingYouFM.ets       # 欢FM
│   └── rulesource/           # 本地规则导入、持久化、HTTP、DOM/JSON/正则、QuickJS 与分发
├── model/                    # Book / BookSource / LocalRuleSource / PlayerState
├── theme/                    # Theme 常量
├── utils/                    # SearchCache / DataSource / WindowUtils 等
└── widget/                   # 桌面播放卡片（PlayerFormAbility）
```

> 历史文档曾写过 `services/`、`models/`、`viewmodels/`、`service/js/`、`service/rule/`，与当前代码不符。  
> **当前没有** V1 viewmodel 层，也没有恢复旧版可直接访问平台能力、无预算执行任意 JS 的客户端规则引擎。
> 页面直接持 `@Local` + Service 单例；在线来源由 `BuiltInSourceRegistry` 与隔离的 `LocalRuleSourceRepository` 聚合。

## 内容架构（重要）

```
SearchPage
├── SourceDataService.getEnabledSources()
│   ├── BuiltInSourceRegistry（始终先加入）
│   │   └── 欢FM（huan_fm）
│   └── LocalRuleSourceRepository（仅加入已启用、兼容的本地规则源）
└── KkBiqugeTextSource（既有文本搜索任务）

BookSourceService
├── 命中内置源 → BuiltInDispatcher（原搜索/详情/目录/播放链不变）
└── 非内置源 → LocalRuleSourceRepository → LocalRuleDispatcher
      ├── URL / Header / GET / POST / Cookie / `@put` / `@get`
      ├── JSONPath / CSS / XPath / 正则 / 紧凑规则组
      ├── `@js` / `jsLib` → taskpool → 有界 QuickJS 独立 context
      └── 搜索 → 详情 → 目录 → 正文或音频地址
```

- 搜索：**多源并行**（内置源 + 已启用本地规则源 + 既有文本源），按 `sourceUrl + bookUrl` 去重
- 分发：`BookSourceService` 先检查 `BuiltInSourceRegistry`，只有非内置来源才进入本地规则旁路
- 开关：本地书源的 `enabled` 只控制是否参与新搜索；只要来源仍安装且兼容，已收藏书的详情、目录、正文和音频解析继续可用
- 隔离：单个规则源或本地规则数据库失败时降级为仅内置源，不改变欢FM及现有播放链行为
- 首页推荐 / 分类 / 发现仍只使用内置源；本地规则源当前只接入搜索、详情、目录、正文和音频解析

### 本地规则源兼容边界

- 导入入口：**我的 → 书源**，与设置同级；可从系统文件选择器读取本地 `.json`，也可粘贴单个 JSON、数组、常见列表外壳或 HTTP(S) 导入地址；单次最多解析 1000 个来源，本地文件与在线导入正文上限 10 MiB，单个来源落库上限 512 KiB
- 内容类型：支持文本、音频及按文本处理的 Web 文件源；漫画源和未知类型保留兼容原因但默认停用
- 规则形态：支持结构化 `ruleSearch`、`ruleBookInfo`、`ruleToc`、`ruleContent`，以及阅读常见的 `@{bookList=...;name=...}` 紧凑规则组；无法解析的紧凑搜索规则才标记为不兼容
- 请求能力：仅允许 HTTP(S)，支持搜索词/页码/来源变量模板、`@put` / `@get`、GET/POST、宽松 JSON 选项、Header、charset、有限重试及 Cookie 管理
- 提取能力：JSONPath 支持属性、下标/并集、负下标、切片、通配、递归下降，以及比较、存在、正则、`&&` / `||` / `!` / 括号过滤；CSS 额外兼容 `:contains` / `:eq` / `:lt` / `:gt` / `:first` / `:last`，并支持 XPath、字段正则、正文净化及 `||` / `&&` / `%%` 组合
- 脚本能力：规则字段中的 `@js` / `js:` / `<js>` 与来源级 `jsLib` 由 `LocalRuleScriptRuntime` 执行，兼容 `java.ajax/ajaxAll/get/post`、Base64/Hex/HTML/MD5/URL/UUID、变量、来源、书籍/章节和 Cookie 等常用子集；脚本网络采用“动作请求 → 原生 HTTP → 响应重放”
- 沙箱限制：每次在 taskpool 创建独立 QuickJS context，默认 1000 ms、heap 64 MiB、stack 256 KiB，并限制 pending jobs、脚本/输入和动作响应预算，native interrupt 提供硬超时，`finally` 释放 context；禁止直接 `fetch` / XHR / WebSocket、Android/Java 平台对象、动态代码、文件和数据库访问
- DOM 与登录边界：隐藏 ArkWeb 仍只用 `DOMParser` 解析已下载 HTML。独立的 `RuleSourceLoginPage` 是唯一远程 ArkWeb 入口，只加载 HTTPS，使用隐私模式且不暴露平台桥接；进入前注入当前书源在目标 origin 的 Cookie，退出时写回加密数据库并清空 Web 会话。站点 Cookie 不发送给聚合服务
- 状态管理：导入时扫描兼容性；不兼容来源显示明确原因且禁止启用。搜索测试会保存 `待测试 / 可用 / 测试失败 / 暂不兼容` 状态
- 持久化：来源、专用登录会话和按 `source_url + origin` 隔离的 Cookie 分表保存在 S2 加密关系库；同 URL 重导保留登录态，删除来源会同步删除会话与 Cookie。系统备份迁移清洗后的完整可执行定义，但不迁移实际登录会话、Cookie、敏感 Header Token 或原始书源 JSON；恢复后来源回到“待测试”

### 与「摸鱼听书」类 App 的区别

摸鱼听书等第三方 APK 的后台是**闭源插件 + 账号体系**，不能作为 App 的书源地址。当前 App 没有服务器地址配置入口；`server/` 仅保留为独立工程。

## 核心服务

| 服务 | 职责 |
|---|---|
| `AudioService` | AVPlayer 单例，焦点、续播、睡眠定时、在线媒体系统缓存、章节预解析 |
| `AVSessionService` | 锁屏/控制中心媒体卡片，倍速、上一集、下一集与收藏控制 |
| `BackgroundTaskService` | `audioPlayback` 长时任务 |
| `BookSourceService` | 内置源优先、本地规则旁路的统一门面（search/info/toc/content/audio；explore/home 仍为内置源） |
| `SourceDataService` | 聚合内置源和已安装本地规则源；数据库异常时只返回内置源 |
| `BuiltInDispatcher` / `BuiltInSourceRegistry` | 按内置源 ID 分发到具体实现 |
| `LocalRuleSourceRepository` | 本地规则源、会话及隔离 Cookie 的加密持久化、启停、批量导入和删除 |
| `LocalRuleDispatcher` / `LocalRuleStageExtractor` | 本地规则搜索、详情、目录、正文/音频阶段分发与受控提取 |
| `GuangYuSourceAdapter` / `GuangYuAuthService` | 光遇聚合的小说+听书原生 API 适配、HTTPS 故障转移及加密 token 会话 |
| `RuleSourceChildService` | 原生聚合源的版本化子源目录、现有搜索接口状态探测及子源官方 HTTPS 登录白名单 |
| `LocalRuleHttpClient` / `LocalRuleWebRuntime` | 按书源与 origin 隔离的 HTTP/Cookie 管理，以及按需 CSS/XPath DOM 解析宿主 |
| `LocalRuleScriptRuntime` / `LocalRuleQuickJsRuntime` | Legado 常用脚本桥接、原生网络动作回放，以及 taskpool 中带硬超时和资源预算的 QuickJS 沙箱 |
| `DataService` | 收藏 / 历史 / 书架本地数据 |
| `PlaybackStore` | 当前播放会话与进度 |
| `DownloadService` / `DownloadStore` / `DownloadPolicy` | 章节下载、策略与持久化 |
| `DownloadExportService` | 通过系统文件选择器将已下载章节导出到文件管理 |
| `ChapterCacheService` | 章节/目录缓存 |
| `PreferenceService` | 偏好（焦点、默认 Tab、隐私同意版本等） |
| `AuthService` | 华为账号（入口默认关闭，需配 AGC client_id） |
| `StatsService` | 听书统计 |
| `UpdateService` | 静默检查更新 |
| `WidgetUpdater` | 桌面卡片刷新 |
| `WebEngineGate` / Web Host | 按需挂载欢FM音频提取和本地规则 DOM 解析宿主 |

## 页面与导航

- 四 Tab：`首页` / `书架` / `记录` / `我的`
- 首页顶栏由固定搜索框和单行横向分类组成；推荐区块在顶栏下方展示，每个区块都有“更多”入口
- 首页首次加载推荐数据时显示骨架屏，不显示“加载推荐中”文案
- 首页推荐态和分类态支持下拉刷新；橙色指示器位于分类栏与列表之间，刷新完成后必须恢复为隐藏状态；搜索结果态不启用下拉刷新
- 双击任一当前 Tab 只滚动到该页顶部，不触发首页刷新
- 记录页使用顶部“编辑”或长按记录进入多选，提供全选、删除和取消；单条记录不显示三点菜单，右侧继续播放按钮保留
- 路由：`Index` + `NavPathStack`（detail / player / import / downloads / settings / ruleSources / ruleSourceLogin / guide / about / privacy …）
- 全局事件：`app.navigate.to.book`、`app.nav.switchTab` 等

页面级交互的现行基线见 [`docs/APP_UI.md`](docs/APP_UI.md)。

## 服务端（`server/`）

详见 [`server/README.md`](server/README.md)。摘要：

- 包名：`jianhu-source-service`（Node ≥ 22）
- 公网入口由实际部署环境配置，仓库说明不记录具体服务地址
- 管理台：`/admin/`
- 能力：音频书源导入与健康检测、网络目录每日同步、按需解析播放地址（不代理音频文件）
- 部署：`server/deploy/compose.yml` + Caddy HTTPS

本地常用：

```bash
cd server
npm install
npm --prefix admin install
npm run typecheck
npm test
npm run admin:build
```

## 开发约定

- 命名：页面 `XxxPage.ets`，组件 `Xxx.ets`，Service `XxxService.ets`，内置源 `IBuiltInSource` 实现类
- 状态：页面 `@Local` + Service 单例；不混用 V1/V2
- 列表：长列表用 `LazyForEach` + 稳定 key（`BookDataSource` / `ChapterDataSource` 等），禁止 index 作为 key
- 搜索：内置源、已启用本地规则源与既有文本源并行聚合；本地失败不得中断其他任务
- 主题：加载图标使用 `AppColor.Brand`（资源 `app_brand`，浅色主题为 `#FF6B3D`），不要回退到系统默认品牌蓝色
- 文案：UI 文案改字符串即可，不要联动改对应 `.ets` 文件名 / 类名
- 新增稳定原生在线源：实现 `IBuiltInSource` → 在 `registerBuiltInSources()` 注册
- 用户导入规则：统一扩展 `service/rulesource/`；脚本只能经 `LocalRuleScriptRuntime` → `LocalRuleQuickJsRuntime.execute()` 执行（门面内部调用 native `evaluateBounded`），不得直接暴露平台、网络、文件/数据库能力或绕过超时和资源预算，登录 WebView 等未支持能力继续放在 `server/`
- 文档：产品或交互发生变化时更新已有的 `README.md`、`CLAUDE.md` 或 `docs/APP_UI.md`；完成后不再有效的一次性修复说明和日期化实施稿直接删除

## Skills（在 `.claude/skills/`）

| skill | 用途 |
|---|---|
| `hmos-arkts-syntax-checker` | 编译 + 语法/错误循环修复（出 HAP/App） |
| `hmos-arkts-deprecated-interface-checker` | 扫描废弃 SDK 接口并给迁移方案 |
| `hmos-arkts-knowledge-retriever` | 检索 ArkTS 语言指南文档 |
| `hmos-arkui-develop-skill` | 写 / 审查 ArkUI 组件 |
| `hmos-arkui-statemgt-migration` | V1 → V2 状态管理迁移 |
| `run-book-source` | 验证 Legado 书源兼容性；客户端覆盖声明式与受限 QuickJS 子集，登录等超出边界的规则仍按服务端方案处理 |

## 常用命令

```bash
# App
ohpm install
hvigorw assembleHap --mode module -p product=default     # debug
hvigorw assembleHap --mode module -p product=release     # release
hvigorw clean

# Server
cd server && npm test && npm run build:all
```

## 测试

- App 单测：`entry/src/test/*.test.ets`（Hypium；含 DownloadPolicy、TingYouRequestPolicy、BuiltInAudioCapability 等）
- Server 单测：`server/test/*.test.ts`（Vitest）
- 改播放 / 内置源 / 下载后，至少在真机验证：搜索、进详情、切章、续播、下载
- 改本地规则导入、运行时或聚合接线后，至少验证：无本地源时内置链不变；导入 → 测试 → 搜索 → 详情 → 文本阅读或音频播放；禁用后不参与搜索但收藏仍可解析；不兼容和失败源不影响其他来源
- 改首页或记录页后，至少在真机验证：首次骨架屏、下拉指示器位置与消失时机、双击 Tab 回顶、编辑/长按多选和继续播放

## 当前进度

- [x] 模板初始化、签名（debug + release）
- [x] 首页 / 书架 / 记录 / 我的 四 Tab
- [x] 首页固定搜索与横向分类、首次骨架屏、下拉刷新、区块“更多”
- [x] 四 Tab 双击回顶
- [x] 记录页统计摘要、编辑/长按多选、批量删除和继续播放
- [x] 播放器、详情、自定义转场
- [x] 欢FM 内置源（加密协议、预热、策略重试）
- [x] 移除 App 云源注册与服务器地址配置，保留欢FM直连
- [x] 书源同级入口、子源目录与内嵌 HTTPS 登录、隔离 Cookie 回写
- [x] 本地规则源旁路（导入、加密存储、测试、启停、文本/音频解析、紧凑规则与受限 QuickJS）
- [x] 服务端聚合、网络目录同步、运维后台、Docker 部署
- [x] AudioService 焦点 / AVSession / 后台播放
- [x] HarmonyOS 7 系统材质、迷你封面单集进度圆环、AVSession 倍速/上下集/收藏控制、在线媒体系统缓存
- [x] 本地播放进度恢复
- [x] 本地音频导入
- [x] 章节下载、下载管理与文件管理导出
- [x] 首启隐私政策同意页、关于/使用说明
- [x] 桌面播放卡片 Widget
- [x] 部分单测（App + Server）
- [ ] 华为账号登录正式上线（AGC / client_id 待配）
- [ ] 崩溃与异常上报
- [ ] 更完整的真机自动化与 E2E
