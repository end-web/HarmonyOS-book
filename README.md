# ListenBook（简·欢）

面向 HarmonyOS 7 手机的听书与小说阅读 App。用户可以导入 Legado/Reader 书源，在设备端搜索、阅读和收听，也可以导入本地音频、下载章节并管理书架与收听记录。个人数据默认保存在本机。

当前版本：`0.1.6`，API 26，`com.huan.listenbook`。版本以 [AppScope/app.json5](AppScope/app.json5) 为准。

## 当前功能

- **书源管理**：本地 JSON、粘贴 JSON、HTTP(S) 地址导入；名称/地址/分组检索、测试状态展示、批量启停与删除、单源测试和批量搜索测试。
- **多源搜索**：已启用且具备搜索规则的导入源每批最多 6 个并行，结果按来源和书籍地址去重，支持有声书/电子书筛选和网格/列表切换。
- **搜索推荐与历史**：从启用来源的真实结果抽取最多 5 本推荐书；最近 20 条搜索历史支持单条删除与清空。
- **首页浏览**：具备首页能力的已启用导入源提供推荐与分类；搜索入口随滚动折叠，分类吸顶，支持骨架屏、下拉刷新和板块“更多”。
- **小说阅读**：在线正文分页、章节跳转、位置恢复；支持字号、行高、翻页方式、主题、自定义底色、纹理和相册背景。
- **音频播放**：章节续播、0.5x–3.0x 倍速、片头片尾跳过、睡眠定时、后台播放、系统媒体控制和在线音频投播。
- **本地与离线**：音频文件和音频 ZIP 导入、章节下载、下载管理，以及将已完成章节导出到系统文件管理。
- **书架与记录**：收藏、内容类型筛选、继续阅读/收听、播放进度、收听统计和历史批量管理。
- **系统集成**：桌面播放卡片、系统备份与在线播放任务跨设备迁移、首启隐私同意与使用说明。

## 使用流程

### 导入和搜索

1. 从“我的 → 书源”打开管理页，通过标题栏加号导入本地 JSON、粘贴规则或填写 HTTP(S) 地址。
2. 根据来源要求登录主账号或网站账号。单源测试在有结果时继续验证详情、目录和正文/音频；批量测试只检查搜索可用性。
3. 在首页进入搜索，输入书名或作者。来源开启“参与搜索”且包含必要搜索规则即可加入聚合，测试状态用于辅助判断可用性。
4. 点击搜索结果进入详情，选择章节阅读或播放。关闭“参与搜索”后，来源定义仍保留，已有收藏可以继续解析。

批量测试不会自动删除失败来源；搜索成功或暂无匹配不代表所有章节都能打开。来源内容取决于上游可用性和当前规则兼容范围。

### 阅读

- 书架中的电子书直接进入阅读页并恢复位置；在线正文按章节和字符位置保存进度。
- 点击正文左右区域翻页，点击中央显示或隐藏“详情 / 章节 / 设置”悬浮栏。
- 章节和设置从底部弹出，目录自动定位当前章节。阅读配色、排版、翻页方式和背景配置会在本机保存。
- 当前文件导入入口提供音频和音频 ZIP；本地 EPUB 导入与书签管理尚未形成完整用户流程。

### 播放与下载

- 播放页可切换章节、调节倍速、设置片头片尾跳过。长按“倍速”恢复 1.0x，长按“跳过”清除设置。
- “定时”提供 15/30/45/60 分钟。开启“章节结束后停止”后，仅在到时仍在播放且本章剩余不超过 10 分钟时等待章节结束；其余情况直接暂停。长按“定时”可取消。
- 迷你播放栏外圈显示当前章节进度，封面保持静止；展开后可进入完整播放页。
- 在线 HTTP(S) 音频可通过“投播”打开系统设备选择器。系统媒体卡片支持倍速、上一集、下一集和收藏。
- 在书籍详情下载章节后，可从下载管理导出已完成章节。系统托管的在线缓存与离线下载分别管理。

### 书架与记录

- 书架支持网格/列表和内容类型筛选，长按拖到删除区可移除书籍。
- 记录页展示统计和已收藏书的收听记录，“未收藏历史”单独查看；右侧播放按钮恢复收听，顶部编辑或长按进入多选删除。
- 双击当前底部 Tab 回到该页顶部。更多操作说明见 App 内“我的 → 使用说明”。

## 技术与架构

| 部分 | 技术 / 目录 | 职责 |
|---|---|---|
| 手机 App | ArkTS、ArkUI V2、HarmonyOS 7 / API 26；`entry/` | 本地规则执行、阅读、播放和设备数据 |
| 规则运行时 | 受限 QuickJS HAR、原生 HTTP、DOM/JSON/正则提取 | 执行 Legado/Reader 兼容子集 |
| 可选服务 | Node.js 22+、Express 5、TypeScript、SQLite；`server/src/` | 独立音频聚合 API、缓存、同步与检测 |
| 运维后台 | Vue 3、TypeScript、Vite、Pinia、Vue Router；`server/admin/` | 来源管理、调试和操作日志 |
| 服务部署 | Docker Compose、Caddy、Reader 内网容器；`server/deploy/` | 独立部署与维护 |

App 内容链路为“导入书源 → 本地加密规则库 → 搜索/详情/目录 → 原生适配或规则提取 → 阅读/播放”。脚本在 taskpool 独立 QuickJS context 中执行，有硬超时和内存、栈、任务、输入输出预算；网络由受控原生请求完成。

主书源账号与站点 Cookie 分开保存。网页登录使用 HTTPS 隐私 WebView，Cookie 按来源和站点隔离后写回加密数据库。

### 页面、接口与数据

| 页面 / 流程 | 服务 | 数据 |
|---|---|---|
| 首页、分类、更多 | `BookSourceService` | 具备首页能力的已启用导入源 |
| 搜索、推荐与历史 | `SourceDataService`、`BookSourceService`、`PreferenceService` | 导入源、搜索缓存、最近 20 条关键词 |
| 详情与小说阅读 | `BookSourceService`、`DataService`、`OnlineTextPaginator` | 书籍/目录缓存、正文、阅读位置和设置 |
| 播放、下载、导出 | `AudioService`、`AVSessionService`、`DownloadService`、`DownloadExportService` | 音频 URL/Header、播放进度和本地文件 |
| 书源与账号管理 | `LocalRuleSourceRepository`、`RuleSourceAccountService` | 加密 `rule_sources.db` 中的来源、主会话、站点 Cookie |
| 书架、收听记录 | `PreferenceService`、`StatsService`、`PlaybackStore` | 本地收藏、历史、统计和播放快照 |

### 数据保存

书架、历史、播放与阅读位置、设置均在设备本地保存。系统备份使用白名单快照，迁移在线收藏、收听记录、播放进度、统计、通用设置、在线书籍元数据和清洗后的书源定义；恢复的来源回到“待测试”。

实际书源登录态、Cookie、敏感 Token、原始书源 JSON、离线下载和本地导入文件不进入该快照；独立阅读位置与阅读设置也不在当前备份范围。跨设备续播迁移的是在线播放任务，不是全量内容或账号数据。

## 项目结构

```text
entry/
  src/main/ets/
    pages/                 页面与导航
    components/            播放、书卡与阅读组件
    service/
      rulesource/          规则导入、账号、HTTP、提取、QuickJS 与来源适配
      text/                在线分页、阅读位置与阅读设置
    model/ theme/ utils/   模型、主题和工具
    widget/                桌面播放卡片
  src/test/                App 单元测试
  src/ohosTest/            设备测试
  libs/quickjs.har          受限 QuickJS 双 ABI 依赖
server/
  src/                     Express API、Provider、SQLite 与同步
  admin/                   Vue 运维后台
  deploy/                  Docker、Caddy 与备份脚本
docs/APP_UI.md             当前页面行为与回归清单
third_party/quickjs/       QuickJS 源码、修改说明与许可
scripts/build-quickjs.ps1  HAR 构建脚本
CLAUDE.md                 开发架构与数据说明
AGENTS.md                 协作与工程约定
```

## 开发与验证

使用支持 HarmonyOS SDK API 26 的 DevEco Studio，在本机 Signing Configs 配置签名。不要提交证书、口令或 `build-profile.json5` 的本机改动。

Agent 开发流程：修改 `.ets` 后先运行 `arkts_check`，再运行 `build_project` 增量构建，成功后 `start_app`。工具不可用时：

```bash
ohpm install
hvigorw assembleHap --mode module -p product=default
hvigorw assembleHap --mode module -p product=release
```

App 使用 ArkUI V2 状态管理；长列表使用稳定 key；加载态使用 `AppColor.Brand`。具体规则见 [AGENTS.md](AGENTS.md)。

App 单测在 `entry/src/test/`，设备测试在 `entry/src/ohosTest/`。来源改动验证导入、单源/批量测试、搜索、详情、阅读/播放及失败隔离；UI 改动按 [当前交互与回归清单](docs/APP_UI.md) 检查。

## 可选服务工程

`server/` 提供音频聚合 API 和管理员后台，App 当前不注册或配置此服务。管理员可导入音频规则、同步网络目录、检测来源、调试内容链并查看操作日志。

公共 API 使用完整前缀 `/api/v1`：

- `GET /api/v1/health`
- `GET /api/v1/sources`
- `GET /api/v1/audio-books/search?q=&page=`
- `GET /api/v1/audio-books/:id`
- `GET /api/v1/audio-books/:id/chapters`
- `POST /api/v1/audio-chapters/:id/resolve`

响应包络为 `{ code, data, requestId, serverTime }`，成功时 `code === "OK"`。后台入口为 `/admin/`，管理接口使用 `/api/admin`。

```bash
cd server
npm install
npm --prefix admin install
npm run typecheck
npm test
npm run build:all
```

部署、环境变量和运维见 [server/README.md](server/README.md)。Reader 引擎仅在 Docker 内网运行。

## 许可证

MIT License。第三方组件说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
