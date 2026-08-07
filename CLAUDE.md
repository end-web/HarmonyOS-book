# ListenBook（简·欢 / 听友）

纯血鸿蒙听书 App。当前形态：**手机端 + 内置音频源**，不再支持用户导入 Legado 规则书源。

在线内容由两类内置源并行提供：

| 内置源 ID | 显示名 | 接入方式 |
|---|---|---|
| `tingyou_fm` | 听友 FM | App 本地直连 `www.tingyou.fm`（加密协议 + CDN） |
| `jianhu_server` | 简·欢云源 | 调用自建 `server/` 聚合服务；阅读规则在服务端执行 |

本地导入音频、章节下载离线与文件管理导出、桌面播放卡片、隐私同意与使用说明已落地。TV/Pad 暂不做。

## 技术基线

- HarmonyOS 7 / API 26，`targetSdkVersion = compatibleSdkVersion = 26.0.0`，stage 模式
- 当前本机 SDK 为 `HarmonyOS 26.0.0.32 Beta2`；代码只使用该 SDK 已声明并通过构建的 API 26 能力
- 单 module：`entry/`（type=entry，deviceTypes=phone）
- ArkUI 使用 **V2 装饰器**（`@ComponentV2` / `@Local` / `@Param` / `@Event` / `@ObservedV2` / `@Trace`）
- `bundleName`: `com.ylwang.listenbook.tingyou`
- 版本示例：`versionName 0.1.1` / `versionCode 1000001`（以 `AppScope/app.json5` 为准）
- 后台模式：`audioPlayback` + `dataTransfer` + `KEEP_BACKGROUND_RUNNING`
- 网络：`INTERNET`；体感：`VIBRATE`
- 签名配置属于本机私有设置，不提交证书路径、Profile 或口令；请在 DevEco Studio 的 Signing Configs 中本地配置

### HarmonyOS 7 SDK 边界

- UI 使用 API 26 `uiMaterial.ImmersiveMaterial` / `systemMaterial`，统一首页悬浮控件、播放器弹层和配置 Sheet。
- `MiniPlayer` 的小圆封面由官方 `Animator` 驱动：播放时旋转，暂停时定格，继续播放时从当前角度续转；完整播放页封面不旋转。
- `AVSessionService` 向系统媒体中心声明倍速、上一集、下一集和收藏控件，不在系统卡片显示循环模式；倍速变更与 App 播放状态双向同步。
- 在线音频通过 `MediaSource.enableOfflineCache(true)` 使用系统托管缓存；用户主动下载的完整章节仍由 `DownloadService` 持久化，两者不互相替代。
- Beta2 已接入 `setSupportedPlaySpeeds`、`setSupportedLoopModes` 和 `setMediaCenterControlType`；媒体中心控件优先展示倍速，循环模式仅保留 App 内控制。这些增强能力失败时按单项降级，不阻断 AVSession 激活。
- 普通应用不能通过 `fileAccess` 将整个私有沙箱挂载到文件管理；完整下载仍保存在 `context.filesDir`，用户可在下载管理页通过系统 `DocumentViewPicker` 选择目标位置并导出音频副本。

## 仓库结构

```
ListenBook/
├── entry/                    # 鸿蒙 App 主模块
│   └── src/main/ets/         # 业务代码（见下）
├── server/                   # 简·欢云源后端（Express + SQLite + Vue 管理台）
│   ├── src/                  # API / 聚合 / 书源同步
│   ├── admin/                # 运维后台（Vue 3）
│   └── deploy/               # Docker Compose + Caddy
├── docs/
│   └── APP_UI.md             # 当前页面行为与 UI 回归基线
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
│   ├── ProfilePage.ets       # 我的（含云源地址配置）
│   ├── PlayerPage.ets        # 播放器
│   ├── BookDetailPage.ets    # 详情
│   ├── BlockMorePage.ets     # 首页区块「更多」
│   ├── ImportPage.ets        # 本地音频导入
│   ├── DownloadManagerPage.ets
│   ├── SettingsPage.ets / GuidePage.ets / AboutPage.ets / PrivacyPage.ets
├── components/               # MiniPlayer / BookCard 等
├── service/                  # 业务服务（注意：单数）
│   ├── http/                 # HttpClient
│   └── builtin/              # 内置音频源体系
│       ├── BuiltInSourceRegistry.ets
│       ├── BuiltInDispatcher.ets
│       ├── ServerAudioConfig.ets   # 云源 API Base 配置
│       └── sources/
│           ├── TingYouFM.ets       # 听友 FM
│           └── ServerAudioSource.ets  # 简·欢云源
├── model/                    # Book / BookSource / PlayerState
├── theme/                    # Theme 常量
├── utils/                    # SearchCache / DataSource / WindowUtils 等
└── widget/                   # 桌面播放卡片（PlayerFormAbility）
```

> 历史文档曾写过 `services/`、`models/`、`viewmodels/`、`service/js/`、`service/rule/`，与当前代码不符。  
> **当前没有** V1 viewmodel 层、**没有** 客户端 Legado 规则引擎（CSS/JSONPath/JS 沙箱已移除）。  
> 页面直接持 `@Local` + Service 单例；书源数据只来自 `BuiltInSourceRegistry`。

## 内容架构（重要）

```
App
├── 听友 FM (builtin://eprendre/tingyou_fm)
│     └── 本地协议：CDN 静态 JSON + 加密 API + WebView 兜底取 token
└── 简·欢云源 (builtin://eprendre/jianhu_server)
      └── HTTP → ServerAudioConfig.apiBase（默认 https://121.196.223.85/api/v1）
            ├── GET  /audio-books/search
            ├── GET  /audio-books/:id
            ├── GET  /audio-books/:id/chapters
            └── POST /audio-chapters/:id/resolve
                  └── server 内：Reader/Legado 引擎 + 网络目录同步（YCKCEO / AOAOSTAR / Yiove 等）
```

- 搜索：**多源并行**（听友 + 云源），按 `sourceUrl + bookUrl` 去重，见 `SearchCache` / 首页搜索逻辑
- 云源只做路由；搜索结果 `sourceName` 为实际上游音频源名，角标不强制写死「简·欢云源」
- 云源 API 地址可在 **我的 → 云源服务地址** 配置，经 `ServerAudioConfig` 规范化并持久化
- App **不接收、不执行** 阅读规则 JSON；规则只在 `server/` 运行

### 与「摸鱼听书」类 App 的区别

摸鱼听书等第三方 APK 的后台（例如 `http://47.103.62.118/api/v1/`）是**闭源插件 + 账号体系**，接口形状与简·欢云源 **不兼容**，不能把对方 `plugin/list` 一类地址直接填进 `ServerAudioConfig`。  
要对齐的是本仓库 `server/` 暴露的标准接口（见 `server/README.md`）。

## 核心服务

| 服务 | 职责 |
|---|---|
| `AudioService` | AVPlayer 单例，焦点、续播、睡眠定时、在线媒体系统缓存、章节预解析 |
| `AVSessionService` | 锁屏/控制中心媒体卡片，倍速、上一集、下一集与收藏控制 |
| `BackgroundTaskService` | `audioPlayback` 长时任务 |
| `BookSourceService` | 内置源门面（search/info/toc/audio/explore/home） |
| `SourceDataService` | 仅返回已注册内置源列表（无用户规则源 CRUD） |
| `BuiltInDispatcher` / `BuiltInSourceRegistry` | 按 `builtin://eprendre/<id>` 分发到具体源 |
| `ServerAudioConfig` | 云源 `apiBase` 读写、校验、health 探测 |
| `DataService` | 收藏 / 历史 / 书架本地数据 |
| `PlaybackStore` | 当前播放会话与进度 |
| `DownloadService` / `DownloadStore` / `DownloadPolicy` | 章节下载、策略与持久化 |
| `DownloadExportService` | 通过系统文件选择器将已下载章节导出到文件管理 |
| `ChapterCacheService` | 章节/目录缓存 |
| `PreferenceService` | 偏好（焦点、默认 Tab、云源地址、隐私同意版本等） |
| `AuthService` | 华为账号（入口默认关闭，需配 AGC client_id） |
| `StatsService` | 听书统计 |
| `UpdateService` | 静默检查更新 |
| `WidgetUpdater` | 桌面卡片刷新 |
| `WebEngineGate` / `WebViewAudioExtractor` | 按需 Web 引擎（听友 token 等） |

## 页面与导航

- 四 Tab：`首页` / `书架` / `记录` / `我的`
- 首页顶栏由固定搜索框和单行横向分类组成；推荐区块在顶栏下方展示，每个区块都有“更多”入口
- 首页首次加载推荐数据时显示骨架屏，不显示“加载推荐中”文案
- 首页推荐态和分类态支持下拉刷新；橙色指示器位于分类栏与列表之间，刷新完成后必须恢复为隐藏状态；搜索结果态不启用下拉刷新
- 双击任一当前 Tab 只滚动到该页顶部，不触发首页刷新
- 记录页使用顶部“编辑”或长按记录进入多选，提供全选、删除和取消；单条记录不显示三点菜单，右侧继续播放按钮保留
- 路由：`Index` + `NavPathStack`（detail / player / import / downloads / settings / guide / about / privacy …）
- 全局事件：`app.navigate.to.book`、`app.nav.switchTab` 等

页面级交互的现行基线见 [`docs/APP_UI.md`](docs/APP_UI.md)。

## 服务端（`server/`）

详见 [`server/README.md`](server/README.md)。摘要：

- 包名：`jianhu-source-service`（Node ≥ 22）
- 公网示例：`https://121.196.223.85/api/v1/health`
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
- 搜索：多内置源并行聚合
- 主题：加载图标使用 `AppColor.Brand`（资源 `app_brand`，浅色主题为 `#FF6B3D`），不要回退到系统默认品牌蓝色
- 文案：UI 文案改字符串即可，不要联动改对应 `.ets` 文件名 / 类名
- 新增在线源：实现 `IBuiltInSource` → 在 `registerBuiltInSources()` 注册；云端规则型源优先进 `server/`，不要回退客户端规则引擎
- 文档：产品或交互发生变化时更新已有的 `README.md`、`CLAUDE.md` 或 `docs/APP_UI.md`；完成后不再有效的一次性修复说明和日期化实施稿直接删除

## Skills（在 `.claude/skills/`）

| skill | 用途 |
|---|---|
| `hmos-arkts-syntax-checker` | 编译 + 语法/错误循环修复（出 HAP/App） |
| `hmos-arkts-deprecated-interface-checker` | 扫描废弃 SDK 接口并给迁移方案 |
| `hmos-arkts-knowledge-retriever` | 检索 ArkTS 语言指南文档 |
| `hmos-arkui-develop-skill` | 写 / 审查 ArkUI 组件 |
| `hmos-arkui-statemgt-migration` | V1 → V2 状态管理迁移 |
| `run-book-source` | 验证 Legado 书源兼容性（**服务端/规则侧**；App 端已不再跑规则引擎） |

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
- 改播放 / 内置源 / 下载 / 云源配置后，至少在真机验证：搜索、进详情、切章、续播、下载
- 改首页或记录页后，至少在真机验证：首次骨架屏、下拉指示器位置与消失时机、双击 Tab 回顶、编辑/长按多选和继续播放

## 当前进度

- [x] 模板初始化、签名（debug + release）
- [x] 首页 / 书架 / 记录 / 我的 四 Tab
- [x] 首页固定搜索与横向分类、首次骨架屏、下拉刷新、区块“更多”
- [x] 四 Tab 双击回顶
- [x] 记录页统计摘要、编辑/长按多选、批量删除和继续播放
- [x] 播放器、详情、自定义转场
- [x] 听友 FM 内置源（加密协议、预热、策略重试）
- [x] 简·欢云源 + 可配置 API 地址
- [x] 服务端聚合、网络目录同步、运维后台、Docker 部署
- [x] AudioService 焦点 / AVSession / 后台播放
- [x] HarmonyOS 7 系统材质、迷你封面播放旋转、AVSession 倍速/上下集/收藏控制、在线媒体系统缓存
- [x] 本地播放进度恢复
- [x] 本地音频导入
- [x] 章节下载、下载管理与文件管理导出
- [x] 首启隐私政策同意页、关于/使用说明
- [x] 桌面播放卡片 Widget
- [x] 部分单测（App + Server）
- [ ] 华为账号登录正式上线（AGC / client_id 待配）
- [ ] 崩溃与异常上报
- [ ] 更完整的真机自动化与 E2E
