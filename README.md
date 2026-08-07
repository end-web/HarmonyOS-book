# ListenBook（简·欢 / 听友）

ListenBook 是一套面向 HarmonyOS Next 的听书系统，不只是一个 App，而是由**用户前台、运维后台和云源服务**三部分组成。用户在鸿蒙 App 内搜索、收藏和播放内容；管理员通过 Web 后台维护云端音频来源；Node 服务负责聚合来源并向 App 提供稳定 API。

| 部分 | 使用者 | 代码 / 入口 | 主要职责 |
|---|---|---|---|
| 用户前台 | 听书用户 | `entry/` | 搜索、详情、章节、播放、书架、记录、本地导入、下载、设置和桌面卡片 |
| 运维后台 | 服务管理员 | `server/admin/`、`/admin/` | 运行概览、书源导入与启停、健康检测、搜索/章节/播放链路调试、操作日志 |
| 云源服务 | App 与运维后台 | `server/src/`、`/api/v1`、`/api/admin` | 聚合音频来源、执行服务端规则、标准化书籍与章节数据、解析播放地址、缓存和定时同步 |

三部分边界明确：

- App 只注册内置来源，不加载或执行用户提供的 Legado 规则。
- 听友 FM 由 App 直接访问；简·欢云源通过服务端聚合，两路搜索并行且互不影响。
- 书架、播放记录、每本书进度和设置默认保存在设备本地，不上传到云源服务。
- 云源服务只返回真实音频地址和必要请求头，不代理音频流，也不保存用户的收听记录。
- 运维后台不是用户听书网页，它只管理服务端来源和运行状态。

> 详细架构与目录约定见 [`CLAUDE.md`](CLAUDE.md)；App 当前交互见 [`docs/APP_UI.md`](docs/APP_UI.md)；服务端运维见 [`server/README.md`](server/README.md)；协作规范见 [`AGENTS.md`](AGENTS.md)。

## 功能特性

### 用户前台

- **双路在线内容**：听友 FM 本地协议 + 简·欢云源聚合 API。
- **首页浏览体验**：HarmonyOS 7 沉浸材质搜索/分类控件、首次进入骨架屏、下拉刷新和每个推荐板块的“更多”入口。
- **完整收听流程**：多源搜索、书籍详情、章节目录、播放地址解析与续播。
- **播放状态反馈**：底部迷你播放栏的小圆封面随播放旋转，暂停时定格并从当前角度续转。
- **系统级播放**：AVPlayer、音频焦点、锁屏/控制中心上一集、下一集、倍速和收藏控制；系统卡片不显示循环模式，另支持后台长时任务和睡眠定时。
- **本地内容与离线能力**：导入音频文件、按章下载、下载管理、本地播放，以及将已下载章节导出到系统文件管理。
- **个人数据**：书架、收藏、收听记录、整本书进度统计和每本书独立播放进度。
- **记录管理**：顶部编辑或长按进入多选，支持全选和批量删除，并保留单书继续播放入口。
- **系统集成**：桌面播放卡片、首启隐私同意、使用说明和云源地址配置。

### 运维后台

- **运行概览**：启用来源数量、来源健康率、最近检测响应和健康脉冲。
- **书源管理**：导入 `bookSourceType = 1` 的阅读音频源，启用、停用、导出、删除和单源检测。
- **目录同步**：查看网络目录状态并手动触发同步；服务端也会按计划自动同步。
- **链路调试**：在一个页面完成搜索、查看章节和解析播放地址的端到端验证。
- **操作审计**：查看后台登录、来源导入、配置变更和检测等操作记录。

### 云源服务

- **稳定公共 API**：统一输出搜索、书籍详情、章节目录和播放解析结果。
- **来源适配**：Reader/Legado 音频规则 Provider、开放播客/公版目录及专有音频 API Provider。
- **可靠性治理**：来源隔离、超时控制、限流、健康检测、失败降级和 SQLite WAL 缓存。
- **自动运维**：网络目录同步、来源版本留档、健康事件、审计日志和数据库备份。
- **安全入口**：管理会话、密码哈希、Helmet、Caddy HTTPS；Reader 仅在 Docker 内网开放。

## 技术栈

| 层级 | 技术 |
|---|---|
| App | HarmonyOS Next Stage、ArkTS、ArkUI V2 |
| SDK | HarmonyOS 7 / API 26，`targetSdkVersion = compatibleSdkVersion = 26.0.0` |
| bundleName | `com.ylwang.listenbook.tingyou` |
| 运维后台 | Vue 3、TypeScript、Vite、Pinia、Vue Router |
| 云源服务 | Node.js 22+、Express 5、TypeScript、SQLite |
| 部署 | Docker Compose、Caddy、Reader 内网容器 |

## 架构一览

```
┌──────────────────────────┐       直连       ┌──────────────────┐
│ HarmonyOS 用户前台 entry/ │ ───────────────► │ tingyou.fm       │
│ 首页 / 书架 / 记录 / 我的  │                  └──────────────────┘
└─────────────┬────────────┘
              │ HTTPS /api/v1
              ▼
┌──────────────────────────────────────────────────────────────┐
│ Caddy 公网入口                                                │
│  ├─ /admin/     Vue 3 运维后台 ───────┐                      │
│  ├─ /api/admin  管理接口 ◄────────────┘                      │
│  └─ /api/v1     App 公共接口                                 │
└──────────────────────────┬───────────────────────────────────┘
                           ▼
┌──────────────────────────────────────────────────────────────┐
│ Node / Express 云源服务                                       │
│ CatalogService │ Provider 适配 │ 缓存 │ 健康检测 │ 目录同步   │
└───────────────┬──────────────────────────────┬───────────────┘
                ▼                              ▼
       ┌─────────────────┐          ┌──────────────────────────┐
       │ SQLite          │          │ Reader 内网服务 / 上游源 │
       │ 来源/书籍/章节/日志│          │ 不直接暴露到公网          │
       └─────────────────┘          └──────────────────────────┘
```

App **不执行** Legado 规则 JSON；规则只在服务端运行。

## 页面、接口与数据

| 页面或流程 | 调用层 | 接口 / 数据 |
|---|---|---|
| App 首页推荐、分类与搜索 | `HomePage`、`BookSourceService`、内置源分发器 | 听友 FM 首页区块与分类直连；搜索并行调用听友 FM 和 `GET /api/v1/audio-books/search` |
| App 书籍详情与章节 | `ServerAudioSource`、`DataService` | `GET /api/v1/audio-books/:id`、`GET /api/v1/audio-books/:id/chapters`；本地 TOC sidecar 缓存 |
| App 播放与下载 | `AudioService`、`DownloadService` | `POST /api/v1/audio-chapters/:id/resolve`；音频直连上游或写入设备沙箱 |
| App 收听记录 | `ReadingStatsPage`、`StatsService`、`PreferenceService` | 本地统计、播放历史和每本书进度；编辑模式批量管理，不使用服务端用户表 |
| App 书架与设置 | `PreferenceService`、`DataService` | 设备 Preferences、本地书籍索引和章节文件；不使用服务端用户表 |
| 后台运行概览 | Vue `DashboardView` | `GET /api/admin/summary`；`sources`、`health_events` |
| 后台书源管理 | Vue `SourcesView` | `/api/admin/sources`、`/api/admin/source-catalogs`；`sources`、`source_versions`、`source_catalogs` |
| 后台链路调试 | Vue `DebugView` | `GET /api/admin/debug/search`，并串联书籍、章节和播放解析能力 |
| 后台操作日志 | Vue `LogsView` | `GET /api/admin/logs`；`audit_logs` |

## 项目结构

```
ListenBook/
├── entry/src/main/ets/     # 鸿蒙业务代码
│   ├── pages/              # 首页/书架/记录/我的 + 播放器/详情/下载…
│   ├── service/            # 播放、下载、偏好、内置源
│   │   └── builtin/        # TingYouFM / ServerAudioSource
│   ├── model/ components/ theme/ utils/ widget/
├── server/
│   ├── src/                # Express API、Provider、SQLite、同步与健康检测
│   ├── admin/              # Vue 3 运维后台
│   └── deploy/             # Docker Compose、Caddy、备份脚本
├── docs/
│   └── APP_UI.md           # App 当前页面与交互基线
├── CLAUDE.md               # 项目说明（给开发/Agent 的真相源）
└── AGENTS.md               # 仓库协作约定
```

## 核心服务（App）

| 服务 | 职责 |
|---|---|
| `AudioService` | AVPlayer 播放核心、音频焦点、后台任务、AVSession、在线媒体系统缓存、续播和进度落盘 |
| `BookSourceService` | 内置来源统一门面和搜索、详情、目录、播放解析分发 |
| `BuiltInSourceRegistry` | 注册 `tingyou_fm` / `jianhu_server` |
| `ServerAudioConfig` | 云源 API Base（默认 `https://121.196.223.85/api/v1`） |
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

## 云源 API（摘要）

默认 Base：`https://121.196.223.85/api/v1`

- `GET /health`
- `GET /audio-books/search?q=&page=`
- `GET /audio-books/:id`
- `GET /audio-books/:id/chapters`
- `POST /audio-chapters/:id/resolve`

响应包络：`{ code, data, requestId, serverTime }`，成功时 `code === "OK"`。

> 其它听书 APK 的私有后台地址（插件列表 / 卡密体系）与本接口 **不兼容**，不能直接填入 App 云源配置。

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
- 新增规则型音频源：优先加在 `server/`，App 侧只扩 `IBuiltInSource` 或继续走云源

## 测试

- App：`entry/src/test/*.test.ets`（Hypium）
- Server：`cd server && npm test`（Vitest）
- App UI 改动还需真机检查：首页首次骨架、下拉刷新收尾、双击 Tab 回顶，以及记录页编辑/长按多选。

## 许可证

MIT License

## 相关链接

- [HarmonyOS 应用开发指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/application-dev-guide-V5)
- [ArkUI 组件参考](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/ts-components-V5)
