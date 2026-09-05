# ListenBook（简·欢）

面向 HarmonyOS 7 手机的本地优先听书与小说阅读 App。在线内容由用户导入的书源提供，规则在设备端执行；支持本地音频导入、章节下载、书架、收听记录、阅读设置、系统媒体控制与桌面播放卡片。`server/` 是可选独立聚合服务和运维后台，App 没有服务器地址配置入口。

本文描述当前代码，页面行为见 [docs/APP_UI.md](docs/APP_UI.md)，开发约束见 [AGENTS.md](AGENTS.md)，服务端使用见 [server/README.md](server/README.md)。

## 技术基线

- HarmonyOS 7 / API 26；`targetSdkVersion = compatibleSdkVersion = 26.0.0`。
- Stage 模式，单模块 `entry/`，设备类型仅 `phone`。
- ArkTS + ArkUI V2；页面使用 `@Local` 和 Service 单例。
- `bundleName = com.huan.listenbook`；当前 `versionName = 0.1.6`、`versionCode = 1000006`，以 `AppScope/app.json5` 为准。
- 后台模式为 `audioPlayback`、`dataTransfer`，权限包括网络、振动和长时后台运行。
- `entry/libs/quickjs.har` 为 arm64-v8a / x86_64 双 ABI 本地依赖；源码和构建脚本在 `third_party/quickjs/`、`scripts/build-quickjs.ps1`。
- 签名在本机 DevEco Studio 配置，`build-profile.json5` 含私有签名信息，禁止提交其中的本机改动。

## 页面、服务与数据

| 页面 / 流程 | 服务入口 | 数据 |
|---|---|---|
| 首页推荐、分类、更多 | `HomePage` / `BlockMorePage` → `BookSourceService` → `TingYouSourceAdapter` | 已导入且启用的听友来源提供首页与分类 |
| 搜索和搜索推荐 | `SearchPage` → `SourceDataService` → `BookSourceService` | 已启用且具备搜索规则的导入源、`SearchCache`、本地搜索历史 |
| 详情、目录 | `BookDetailPage` → `BookSourceService` → 对应分发器 | `Book`、`Chapter`、书籍索引和按书拆分的目录缓存 |
| 小说阅读 | `ReaderPage` → `BookSourceService`、`OnlineTextPaginator` | 章节正文缓存、字符位置、阅读设置 |
| 播放、下载、导出 | `AudioService`、`AVSessionService`、`DownloadService`、`DownloadExportService` | 音频 URL / Header、播放进度、沙箱音频和导出副本 |
| 书源管理 | `RuleSourcePage` → 导入解析器、仓库、批量测试器 | 加密 `rule_sources.db` |
| 主账号、子源、网页登录 | `RuleSourceAccountPage` / `RuleSourceChildrenPage` / `RuleSourceLoginPage` | 来源主会话、按来源和站点隔离的 Cookie |
| 书架、记录、未收藏历史 | `FavoritePage` / `ReadingStatsPage` / `UnfavoritedHistoryPage` → `PreferenceService`、`StatsService` | 收藏、收听历史、累计统计和播放位置 |
| 本地音频导入 | `ImportPage` → `DataService` | 音频文件或音频 ZIP、书籍信息和沙箱文件 |
| 系统备份、跨设备续播 | `AppBackupService`、`ContinuationService` | 白名单备份快照、最小播放迁移载荷 |

主导航是 `Index` + `NavPathStack`，`MainPage` 承载“首页 / 书架 / 记录 / 我的”。搜索、详情、阅读、播放器、导入、下载和书源管理使用独立路由。

## 内容分发

```text
用户导入 JSON / HTTP(S) 地址
  -> LocalRuleSourceImportParser
  -> LocalRuleSourceRepository (rule_sources.db)
  -> SourceDataService
  -> BookSourceService
       -> NativeRuleSourceDispatcher -> 光遇 / 书山原生适配
       -> LocalRuleDispatcher
            -> TingYouSourceAdapter（识别出的听友来源）
            -> 声明式提取 / LocalRuleScriptRuntime / 受控 HTTP
```

- `SourceDataService` 只聚合导入源，排除 `builtin://` 地址；数据库读取失败时返回空列表或未找到来源。
- 搜索每批最多并行执行 6 个来源，按 `sourceUrl + bookUrl` 去重；单源失败独立处理，过期搜索结果不覆盖新搜索。
- `enabled`、有效来源地址及搜索必需规则共同决定是否参与新搜索。测试状态是诊断信息，不要求先变为“可用”才能搜索。
- 关闭来源不会删除定义，已有收藏仍可按来源解析；删除来源会同时删除主会话、Cookie 和脚本持久化状态。
- 首页及分类查找已启用的听友导入源；其他导入源参与搜索和内容解析，不自动生成首页板块。
- 搜索页推荐使用来源真实返回的书籍，优先尝试首页板块，不足时从来源搜索结果补充，再去重随机抽取最多 5 本。
- 启动流程不调用 `registerBuiltInSources()`，`BookSourceService` 不调用 `BuiltInDispatcher`，搜索页不启动 `KkBiqugeTextSource` 独立任务。相关实现和验证页面仍在仓库，但不代表当前产品入口；`service/builtin/` 中仍有被引用的公共工具，不能按目录整体删除。

### 导入与测试

- 支持本地 `.json`、粘贴 JSON、数组或常见列表外壳、HTTP(S) 导入地址；单次最多 1000 个来源，导入正文上限 10 MiB，单源落库上限 512 KiB。
- 接收结构化规则和 `@{...}` 紧凑规则，保存来源类型、登录定义、`jsLib`、变量和规则字段。
- `LocalRuleSourceCodec` 将编辑字段合并回原始定义，保留扩展字段及未改动的紧凑规则；编辑器提供发现、登录、完整 JSON 校验与单源导出，保存后清理来源列表缓存。
- 导入后标记“待测试”，保留能力提示和来源启用设置。不能依据漫画、未知类型、脚本登录字段或提示信息推断来源已被禁用；当前非音频类型尝试通用文本内容链，这不等于已有漫画阅读器。
- 单源测试由 `BookSourceService.testLocalSource()` 执行：普通来源有搜索结果时继续验证详情、目录和正文或音频解析；正常请求但无结果时保留来源并给出说明。
- 光遇单源测试确认小说和听书搜索，只执行听书内容链验证；书山验证小说与听书内容链。需要主账号的来源先进入账号页。
- 批量测试由 `LocalRuleSourceBulkTester` 调用 `testLocalSourceAvailability()`，最多 6 个并发任务，完成一个补入一个，仅探测搜索可用性；失败来源保留并记录原因，不自动删除，也不改变启用开关。
- 批量启停和删除使用 400 条谓词分块及事务；同 URL 重导保留主会话和 Cookie，删除则清理对应凭据。

### 规则执行与账号边界

- 请求经 `LocalRuleHttpClient`，支持 HTTP(S)、GET/POST/PUT/PATCH/DELETE/HEAD、Header、编码、有限重试、变量模板和隔离 Cookie。重定向最多 5 次，跨域删除敏感请求头；脚本 response 可读取非 2xx 正文、状态和大小写无关的 Header。`data:` 支持百分号/Base64 内容，发出网络请求需显式 request 选项。
- `LocalRuleStageExtractor` 处理 JSONPath、CSS、XPath、正则、正文净化及组合规则；支持相对 JSON 路径、尾部 `@put`、JS 字段模板和脚本数组后续选择器。JSON 请求体按字段替换模板，保留关键词中的引号和反斜线。
- `@js` / `jsLib` 经 `LocalRuleScriptRuntime` → `LocalRuleQuickJsRuntime.execute()` → taskpool → native `evaluateBounded`。每次创建独立 context，在 `finally` 释放；默认 1000 ms、64 MiB heap、256 KiB stack，并限制 pending jobs 与输入输出。
- 脚本不能直接访问平台、文件、数据库或不受控网络；`java.ajax` 等兼容网络动作通过原生 HTTP 请求与结果回放完成。
- `LocalRuleScriptCompat` 提供二进制 Base64/Hex、表单编码、Java 字符串和集合白名单、摘要/HMAC/AES、繁简转换、章节数字及时间格式。动作最多 64 次，其中网络最多 32 次；Date 与随机数在重放中稳定。来源声明的远程 `jsLib` 最多 8 个、合计 2 MiB，按来源和会话隔离缓存 5 分钟。
- `source.getVariable/setVariable`、`source.get/put`、有期限的 `cache` 和登录信息/请求头存入加密 `rule_source_script_state`。同来源脚本串行提交状态，失败脚本不提交；不同来源隔离，网络重放不会重复累加持久化状态。
- JS 章节地址由 `LocalRuleChapterRequest` 延迟至打开章节时执行；稳定章节 URL 携带有界元素上下文，支持重新进入后的请求重建和时效签名刷新。
- `LocalRulePanelService` 解析通用发现与登录表单、嵌套分组及选项标签/值；登录按钮可调用 `loginUrl` 中的函数，网页动作进入 HTTPS 登录路由。`ruleExplore` 通过现有导入源分发器执行，缺少必要规则时回退搜索规则。首页推荐仍使用原听友入口。
- `LocalRuleDebugService` 提供真实阶段及全链路调试、取消检查和脱敏诊断。`concurrentRate` 兼容空值/0（不限流）、正整数（请求间隔毫秒）、负整数（同时请求数）和次数/毫秒窗口；无法识别的可选配置仅记诊断，不阻断请求，并发名额在请求结束后释放。声明式 `session` 可将当前 URL 查询参数映射为 Cookie、生成稳定设备 Cookie 并设置 Referer，状态仍按来源和目标站点隔离。
- 普通 DOM 宿主只解析已下载 HTML；显式 `webView` 使用独立隐私 ArkWeb 渲染网站脚本，主文档由原生响应提供，避免重复提交 POST。限制 128 个资源请求、16 个站点、5 次导航和总时限，退出清空网页会话。`webJs` 在 QuickJS 中只读 DOM/页面数据快照，`bodyJs` 在同一受限运行时转换响应；两者不会获得浏览器桥接或额外网络能力。
- 网页音频嗅探使用资源 URL 和 audio/video/source 节点，并应用 `sourceRegex`。音频规则返回的 URL 选项拆分为实际播放地址与请求头；错误文字不能作为相对音频地址报告成功。
- `RuleSourceLoginPage` 提供 HTTPS 隐私 WebView，不暴露平台桥接；站点 Cookie 按 `source_url + origin` 回写加密数据库，完成时执行配置的登录检查。登录页与网页渲染通过 `LocalRuleWebSession` 互斥使用隐私 Cookie，退出时清空 Web 会话。
- 光遇、书山主账号通过 `RuleSourceAccountService` 分发到各自原生账号服务；主会话与子源网站 Cookie 独立保存。
- 当前只实现 Legado/Reader 的兼容子集，导入成功和批量搜索通过均不保证每个来源的完整内容链可用。

## 阅读与播放

- 在线小说用 `OnlineTextPaginator` 分页，按章节标题或索引及 `charOffset` 恢复位置；切换字号和窗口尺寸后重新分页。章节正文有内存缓存、请求合并和相邻章节预取。
- 分页前为每个非空正文段落统一添加两个全角空格，测量与显示共用排版文本；页起止偏移映射回清洗后的原文，新增缩进不改变阅读进度的字符坐标。跨页续行不补缩进，正文段落不做启发式合并。
- `ReaderPage` 还保留已有 EPUB 路径的 ReaderKit 分支及 `EpubReaderComponent`；当前 `ImportPage` 只导入音频和音频 ZIP，没有完整的本地 EPUB 导入、独立电子书库或书签管理入口。
- 阅读页默认隐藏“详情 / 章节 / 设置”悬浮栏；阅读设置包括字号、行高、翻页方式、五种主题、自定义底色、纸纹、布纹和相册背景。
- AVPlayer 负责播放、音频焦点和续播，`AVSessionService` 对接系统倍速、上下集和收藏，后台任务维持收听。
- 播放页支持 0.5x–3.0x 倍速、片头片尾跳过、睡眠定时和 HTTP(S) URL 投播。定时预设为 15/30/45/60 分钟，智能停止仅在到时仍在播放且本章剩余时长大于 0、不超过 10 分钟时等待章节结束。
- 在线 `MediaSource` 系统缓存与用户主动章节下载分开；下载文件可经系统文件选择器导出副本。
- 迷你播放器封面和完整播放页封面保持静止，迷你播放器外圈展示当前集进度。

## 本地存储

| 存储 | 内容 |
|---|---|
| `rule_sources.db` / `rule_sources` | 来源地址、名称、类型、分组、规则 JSON、启用与测试状态、排序 |
| `rule_sources.db` / `rule_source_sessions` | 按 `source_url` 保存主会话 token、device ID、账号标签 |
| `rule_sources.db` / `rule_source_cookies` | 按 `source_url + origin` 保存站点 Cookie |
| `PreferenceService`、`PlaybackStore`、`StatsService` | 收藏、收听历史、播放快照、章节进度、统计和通用设置；搜索历史最多 20 条 |
| `online_text_reading_progress` Preferences | 按书保存章节、DOM/字符位置、页偏移和章节标题 |
| `text_reading_settings` Preferences | 字号、行高、主题、翻页方式、背景配置 |
| `DataService` | `cached_books_v1.json` 书籍索引、拆分目录和本地导入书 |
| `files/reader_bg` | 用户选择的阅读背景图片副本 |
| `files/backup/listenbook_state.json` | 系统备份白名单快照 |

规则数据库使用 S2 安全级别和加密。备份迁移在线收藏、收听记录和播放进度、统计、通用设置、书籍元数据及清洗后的书源定义；不迁移实际登录会话、Cookie、敏感 Header Token、原始书源 JSON、下载音频及本地导入文件。来源恢复后回到“待测试”。独立阅读 Preferences 不在当前 `AppBackupService` 快照中。

跨设备迁移携带在线书当前章节、原始章节地址、进度、时长、倍速和播放状态，目标设备再补齐目录；不是全量文件或书源账号同步。

## 仓库结构

```text
entry/src/main/ets/
  entryability/          UIAbility、启动与跨设备恢复
  entrybackupability/    系统备份扩展
  pages/                 路由页面与四 Tab 内容
  components/            播放器、书卡、阅读设置与背景等组件
  service/               播放、下载、存储、备份及内容门面
    rulesource/          导入、测试、数据库、HTTP、提取、QuickJS
      guangyu/           光遇协议与主账号
      shushan/           书山协议、主账号与正文解密
      tingyou/           听友导入源协议、首页与分类
    text/                在线分页、阅读位置、阅读设置和解析工具
    builtin/             协议与 Web 工具、注册器实现；非当前来源列表入口
  model/                 Book、Chapter、LocalRuleSource、TextReading 等
  theme/                 AppColor、AppMaterial 等主题常量
  utils/                 缓存、稳定标识、数据源、窗口与转场工具
  widget/                桌面播放卡片
entry/libs/quickjs.har    受限 QuickJS 本地依赖
server/                  独立 Express API、Vue 运维后台与 Docker 部署
docs/APP_UI.md           当前交互与回归清单
third_party/quickjs/     QuickJS 源码及许可
scripts/                HAR 构建与图标工具
```

## 开发与验证

1. 修改 `.ets` 前加载 `arkts-grammar-standards`，遵循 [AGENTS.md](AGENTS.md) 的 ArkTS / ArkUI V2 约束。
2. 对修改文件运行 `arkts_check`，再运行 `build_project` 增量构建；成功后用 `start_app` 真机或模拟器验证。发生 ArkTS 错误先加载 `arkts-error-fixes`。
3. 工具不可用时使用 `ohpm install`、`hvigorw assembleHap --mode module -p product=default`；`release` 产品用于发布配置。只在确认缓存问题时清理构建。
4. App 单测位于 `entry/src/test/`，涵盖本地规则、原生适配、批量测试、搜索缓存与历史、在线分页、阅读主题、播放进度和下载策略；设备测试位于 `entry/src/ohosTest/ets/test/`。
   - 书源回归设备类：`LocalRuleCompatibility,LocalRuleFeatures,LocalRuleRuntime,LocalRulePersistence,LocalRuleRequestLimiter`。HTTP/网页集成另启动 `node scripts/local-rule-http-fixture.cjs`，用 HDC 映射 `rport tcp:18997 tcp:18997`，运行 `LocalRuleBrowserIntegration` 并传入 `-s fixtureUrl http://127.0.0.1:18997`；结束后停止服务并移除该映射。
   - `LocalRuleImportedSmoke` 仅在显式传入 `sourceUrl` 时访问实际来源，可用 `importUrl` 临时导入缺失定义，完成后清理临时来源。`SourcePlaybackSmoke` 的 `playbackImportUrl`、`playbackSourceUrl`、`playbackKeyword` 参数覆盖搜索到实际起播和暂停续播，设备测试静音播放。
5. 服务端校验使用 `npm run typecheck`、`npm test`、`npm run build:all`；部署细节见 `server/README.md`。

来源与阅读改动应验证“无导入源空态 → 导入 → 单源/批量测试 → 搜索 → 详情 → 阅读或播放”，以及禁用后的收藏解析、单源失败隔离。播放与下载改动应验证切章、续播、系统控制、下载和导出。UI 改动按 `docs/APP_UI.md` 回归。

华为账号入口当前由 `ENABLE_HW_LOGIN = false` 关闭，模块中的 `client_id` 仍为占位配置。不要将它描述为已上线登录功能。

产品或交互变化直接更新现行文档；已失效的一次性计划和修复说明删除，历史由 Git 保留。
