# ListenBook（简·欢）

ListenBook（简·欢）是一款面向 HarmonyOS Next 的本地优先听书 App。App 支持在设备端导入、执行 Legado/Reader 规则；仓库中的 Node 服务和运维后台作为可选独立工程保留，不是 App 的运行依赖。

| 部分 | 使用者 | 代码 / 入口 | 主要职责 |
|---|---|---|---|
| 用户前台 | 听书用户 | `entry/` | 多源搜索、详情、章节、阅读/播放、书架、记录、本地音频与书源导入、下载、设置和桌面卡片 |
| 运维后台 | 服务管理员 | `server/admin/`、`/admin/` | 运行概览、书源导入与启停、健康检测、搜索/章节/播放链路调试、操作日志 |
| 可选服务工程 | 服务管理员 | `server/src/`、`/api/v1`、`/api/admin` | 独立的聚合、管理和部署工具；App 当前不注册或配置该服务 |

三部分边界明确：

- 用户导入的 Legado/Reader 规则通过独立旁路参与搜索、详情、目录、正文和音频解析。
- 本地规则源或规则数据库失败时只影响对应来源，不能中断其他来源的搜索与播放链。
- 书架、播放记录、每本书进度、设置和书源 Cookie 默认保存在设备本地，不上传到可选服务工程。
- 书源网页登录在 App 内的 HTTPS 隐私 WebView 中完成，Cookie 按书源和站点隔离并写入 S2 加密数据库。
- 运维后台不是用户听书网页，它只管理服务端来源和运行状态。

> 详细架构与目录约定见 [`CLAUDE.md`](CLAUDE.md)；App 当前交互见 [`docs/APP_UI.md`](docs/APP_UI.md)；服务端运维见 [`server/README.md`](server/README.md)；协作规范见 [`AGENTS.md`](AGENTS.md)。

## 功能特性

### 用户前台

- **多源在线内容**：既有文本搜索能力 + 用户导入的本地 Legado/Reader 规则源。
- **首页浏览体验**：HarmonyOS 7 沉浸材质搜索/分类控件、首次进入骨架屏、下拉刷新和每个推荐板块的“更多”入口。
- **完整阅读与收听流程**：多源搜索、书籍详情、章节目录、正文阅读、播放地址解析、跳过片头片尾与章节级续播。
- **播放状态反馈**：底部迷你播放栏的小圆封面保持静止，外圈展示当前章节收听进度。
- **系统级播放**：AVPlayer、音频焦点、锁屏/控制中心上一集、下一集、倍速和收藏控制；系统卡片不显示循环模式，另支持后台长时任务和睡眠定时。
- **本地内容与离线能力**：导入音频文件、按章下载、下载管理、本地播放，以及将已下载章节导出到系统文件管理。
- **个人数据**：书架、收藏、收听记录、整本书进度统计，以及每本书、每章节独立播放进度。
- **记录管理**：顶部编辑或长按进入多选，支持全选和批量删除，并保留单书继续播放入口。
- **本地书源管理**：从“我的 → 书源”导入 JSON 或 HTTP(S) 地址，支持兼容检查、单源搜索测试、启停、聚合子源查看、内嵌登录和删除；关闭“参与搜索”不会破坏已有收藏的解析。
- **系统集成**：桌面播放卡片、首启隐私同意和使用说明。

## App 使用教程

### 开始使用

1. 首次打开 App，阅读并同意隐私政策。App 的书架、记录、阅读进度、播放进度和设置默认保存在本机。
2. 在首页进入搜索，输入书名或作者后提交搜索。首页下拉刷新内容；双击当前底部页签可快速回到顶部。
3. 点击书籍进入详情页，在章节列表选择内容。点击播放按钮开始收听，底部迷你播放栏可展开，点击标题区域进入完整播放页。

### 播放与离线

- 播放页可以切换章节、调整 `0.5x-3.0x` 倍速、设置片头/片尾跳过，并按书籍和章节保存播放进度。长按“倍速”恢复 `1.0x`，长按“跳过”清除跳过设置。
- 点击“定时”选择 `15/30/45/60` 分钟；开启“章节结束后停止”后，定时到达时会尽量播完当前章节再暂停，长按“定时”可取消。
- 需要长期离线收听时，在书籍详情的下载功能中下载章节；系统托管的在线缓存不等同于离线下载。下载管理可将已完成章节导出到系统文件管理。
- 在线音频可通过播放页的“投播”打开系统设备选择器；本地导入音频不支持 URL 投播。锁屏或控制中心媒体卡片支持上一集、下一集、收藏和倍速。

### 电子书阅读

1. 在书架打开电子书会直接进入阅读页，并恢复上次位置。
2. 点击正文左侧或右侧翻页，点击正文中央显示或隐藏“详情 / 章节 / 设置”悬浮栏。
3. 在“设置”中调整字号、行高、翻页方式、阅读主题、自定义底色和背景图案，修改会自动保存；章节面板打开时会定位当前章节。

### 导入书源

1. 打开“我的 → 书源”，点击右上角加号，选择本地 JSON、粘贴书源 JSON，或输入 HTTP(S) 地址导入。
2. 导入后先执行书源测试，确认状态为“可用”再参与搜索。搜索测试按书源独立执行，单个来源失败不会影响其他来源。
3. “参与搜索”只影响新的搜索聚合；关闭后，已有收藏仍可继续解析。需要账号的来源从主账号或子源的“登录”入口进入，Cookie 按书源和站点隔离保存在设备本地。

### 书架与记录

- 书架用于管理收藏和本地内容；长按书籍并拖到删除区可移除书籍，并按提示选择是否删除本地文件。
- 记录页保存收听历史和累计统计。点击记录右侧播放按钮可从上次位置继续，点击“编辑”或长按记录可批量删除。

> 书源内容依赖来源站点的可用性和网络环境。App 内“我的 → 使用说明”也提供上述主要手势和功能入口。

### 运维后台

- **运行概览**：启用来源数量、来源健康率、最近检测响应和健康脉冲。
- **书源管理**：导入 `bookSourceType = 1` 的阅读音频源，启用、停用、导出、删除和单源检测。
- **目录同步**：查看网络目录状态并手动触发同步；服务端也会按计划自动同步。
- **链路调试**：在一个页面完成搜索、查看章节和解析播放地址的端到端验证。
- **操作审计**：查看后台登录、来源导入、配置变更和检测等操作记录。

### 可选服务工程

- **稳定公共 API**：统一输出搜索、书籍详情、章节目录和播放解析结果。
- **来源适配**：Reader/Legado 音频规则 Provider、开放播客/公版目录及专有音频 API Provider。
- **可靠性治理**：来源隔离、超时控制、限流、健康检测、失败降级和 SQLite WAL 缓存。
- **自动运维**：网络目录同步、来源版本留档、健康事件、审计日志和数据库备份。
- **安全入口**：管理会话、密码哈希、Helmet、Caddy HTTPS；Reader 仅在 Docker 内网开放。

## 技术栈

| 层级 | 技术 |
|---|---|
| App | HarmonyOS Next Stage、ArkTS、ArkUI V2、受限 QuickJS HAR |
| SDK | HarmonyOS 7 / API 26，`targetSdkVersion = compatibleSdkVersion = 26.0.0` |
| bundleName | `com.huan.listenbook` |
| 运维后台 | Vue 3、TypeScript、Vite、Pinia、Vue Router |
| 可选服务工程 | Node.js 22+、Express 5、TypeScript、SQLite |
| 部署 | Docker Compose、Caddy、Reader 内网容器 |

## 架构一览

```
┌──────────────────────────┐
│ HarmonyOS 用户前台 entry/ │
│ 首页 / 书架 / 记录 / 我的  │
└─────────────┬────────────┘
              ├─ 本地规则书源 ─► HTTP(S) 站点（JSON / HTML / 文本 / 音频）
              │                  └─ CSS / XPath / JSONPath / Regex / QuickJS 沙箱
              └─ HTTPS 内嵌登录 ─► 站点账号页

可选独立工程（不在 App 请求链中）：
┌──────────────────────────────────────────────────────────────┐
│ Vue 运维后台 + Node / Express 服务                            │
│ CatalogService │ Provider 适配 │ 缓存 │ 健康检测 │ 目录同步   │
└───────────────┬──────────────────────────────┬───────────────┘
                ▼                              ▼
       ┌─────────────────┐          ┌──────────────────────────┐
       │ SQLite          │          │ Reader 内网服务 / 上游源 │
       │ 来源/书籍/章节/日志│          │ 不直接暴露到公网          │
       └─────────────────┘          └──────────────────────────┘
```

App 对用户导入规则只执行当前兼容子集：声明式提取由本地解析器完成，`@js` / `jsLib` 在独立 QuickJS context 中受预算执行。脚本不能直接使用 `fetch`、XHR、WebSocket、Android/Java 平台对象、文件或数据库；网络动作经受控原生 HTTP 回放。服务端完整 Reader/Legado 引擎仍只在 Docker 内网运行。

## 页面、接口与数据

| 页面或流程 | 调用层 | 接口 / 数据 |
|---|---|---|
| App 首页搜索与发现 | `HomePage`、`SearchPage`、`SourceDataService`、`BookSourceService` | 搜索并行聚合已安装规则源和既有文本源，每批最多 6 个本地规则源 |
| App 书籍详情、章节与阅读 | `BookSourceService`、`LocalRuleDispatcher`、`DataService` | 按来源定义请求并提取详情、目录和正文；本地 TOC sidecar 缓存 |
| App 播放与下载 | `AudioService`、`DownloadService`、`BookSourceService` | 本地音频规则解析真实地址和请求头；音频直连上游或写入设备沙箱 |
| App 本地书源管理 | `ProfilePage`、`RuleSourcePage`、`RuleSourceChildrenPage`、`RuleSourceLoginPage` | JSON / HTTP(S) 导入、测试、启停、子源查看和内嵌登录；定义与按 `source_url + origin` 隔离的 Cookie 存入 S2 加密 `rule_sources.db` |
| App 收听记录 | `ReadingStatsPage`、`StatsService`、`PreferenceService` | 本地统计、播放历史和每本书进度；编辑模式批量管理，不使用服务端用户表 |
| App 书架与设置 | `PreferenceService`、`DataService` | 设备 Preferences、本地书籍索引和章节文件；不使用服务端用户表 |
| 后台运行概览 | Vue `DashboardView` | `GET /api/admin/summary`；`sources`、`health_events` |
| 后台书源管理 | Vue `SourcesView` | `/api/admin/sources`、`/api/admin/source-catalogs`；`sources`、`source_versions`、`source_catalogs` |
| 后台链路调试 | Vue `DebugView` | `GET /api/admin/debug/search`，并串联书籍、章节和播放解析能力 |
| 后台操作日志 | Vue `LogsView` | `GET /api/admin/logs`；`audit_logs` |

## 项目结构

```
ListenBook/
├── entry/
│   ├── src/main/ets/       # 鸿蒙业务代码
│   │   ├── pages/          # 首页/书架/记录/我的 + 播放器/详情/下载…
│   │   ├── service/        # 播放、下载、偏好及统一内容分发
│   │   │   └── rulesource/ # 本地规则导入、HTTP、提取、QuickJS 与分发
│   │   └── model/ components/ theme/ utils/ widget/
│   └── libs/quickjs.har    # 双 ABI 受限 QuickJS 本地依赖
├── server/
│   ├── src/                # Express API、Provider、SQLite、同步与健康检测
│   ├── admin/              # Vue 3 运维后台
│   └── deploy/             # Docker Compose、Caddy、备份脚本
├── docs/
│   └── APP_UI.md           # App 当前页面与交互基线
├── third_party/quickjs/    # QuickJS 模块源码、修改说明与许可证
├── scripts/build-quickjs.ps1
├── CLAUDE.md               # 项目说明（给开发/Agent 的真相源）
└── AGENTS.md               # 仓库协作约定
```

## 核心服务（App）

| 服务 | 职责 |
|---|---|
| `AudioService` | AVPlayer 播放核心、音频焦点、后台任务、AVSession、在线媒体系统缓存、续播和进度落盘 |
| `BookSourceService` | 本地规则源和既有文本源的搜索、详情、目录、正文和播放解析门面 |
| `SourceDataService` | 聚合已安装本地规则源；按来源地址查询时读取规则数据库 |
| `LocalRuleSourceRepository` / `LocalRuleDispatcher` | 本地规则源、会话与隔离 Cookie 的加密持久化、测试、启停，以及搜索到正文/音频的阶段分发 |
| `LocalRuleStageExtractor` / `LocalRuleWebRuntime` | JSONPath、CSS、XPath、正则及组合规则提取；ArkWeb 只处理已下载 DOM，不执行站点脚本 |
| `LocalRuleScriptRuntime` / `LocalRuleQuickJsRuntime` | 兼容紧凑规则、`@js` / `jsLib` 和受控 `java.ajax` 等常用桥接；在 taskpool 独立 context 中执行并限制超时、heap、stack、pending jobs 与输入输出 |
| `DownloadService` | 章节下载队列、后台传输、进度通知和离线文件管理 |
| `DownloadExportService` | 调用系统文件选择器，将沙箱内已下载章节复制到用户选择的位置 |
| `DataService` | 本地导入书、缓存书籍索引和按书拆分的章节目录 |
| `PreferenceService` | 书架、历史、每本书播放进度、设置与隐私同意版本 |
| `StatsService` / `PlaybackStore` | 收听时长统计与当前播放会话快照 |

## 核心服务（Server）

| 模块 | 职责 |
|---|---|
| `CatalogService` | 聚合来源，处理搜索、书籍、章节、播放解析和健康检测 |
| `AppDatabase` | SQLite 表结构、缓存、来源版本、健康事件和审计日志 |
| Provider 层 | 对接 Reader/Legado、播客、公版目录和专有音频 API |
| `SourceCatalogSyncService` | 同步 YCKCEO、AOAOSTAR、Yiove 等网络目录并隔离单目录故障 |
| Public Router | 暴露 `/api/v1` 给 App，统一响应包络、限流和错误处理 |
| Admin Router | 提供登录会话、来源管理、调试、缓存清理与日志接口 |

## 可选服务 API（摘要）

该 API 仅供独立部署和运维使用，App 当前没有 API Base 配置入口。

- `GET /health`
- `GET /audio-books/search?q=&page=`
- `GET /audio-books/:id`
- `GET /audio-books/:id/chapters`
- `POST /audio-chapters/:id/resolve`

响应包络：`{ code, data, requestId, serverTime }`，成功时 `code === "OK"`。

> 其它听书 APK 的私有后台地址（插件列表 / 卡密体系）与本接口不兼容，也不是 App 可导入的书源地址。

## 开发指南

### 环境

- DevEco Studio 26.0.0 Beta2 或更新版本
- HarmonyOS SDK 26.0.0（API 26）
- Node.js 22+（仅改 `server/` 时需要）

### App

```bash
ohpm install
hvigorw assembleHap --mode module -p product=default
hvigorw assembleHap --mode module -p product=release
hvigorw clean
```

签名请在本机 DevEco Signing Configs 配置，勿把证书与口令提交进仓库。

### Server

```bash
cd server
npm install
npm --prefix admin install
npm run typecheck
npm test
npm run admin:build
```

Docker 部署见 `server/deploy/` 与 `server/README.md`。

### 开发规范（摘要）

- 只用 ArkUI V2 状态管理
- 长列表 `LazyForEach` + 稳定 key
- 搜索多源并行，单源失败不拖垮整体
- 加载态使用项目主题 `AppColor.Brand`，不要直接使用鸿蒙默认品牌蓝色
- 首页和主 Tab 交互改动需同步 [`docs/APP_UI.md`](docs/APP_UI.md)
- 用户规则兼容能力统一扩展 `service/rulesource/`，不得绕过 `LocalRuleQuickJsRuntime` 直接调用不受限 QuickJS API

## 测试

- App：`entry/src/test/*.test.ets`（Hypium）
- Server：`cd server && npm test`（Vitest）
- 本地规则运行时改动需验证：“导入 → 测试 → 搜索 → 详情 → 阅读或播放”；单源失败不得影响其他来源。
- App UI 改动还需真机检查：首页首次骨架、下拉刷新收尾、双击 Tab 回顶，以及记录页编辑/长按多选。

## 许可证

MIT License

第三方组件及其许可证见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

## 相关链接

- [HarmonyOS 应用开发指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/application-dev-guide-V5)
- [ArkUI 组件参考](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/ts-components-V5)
