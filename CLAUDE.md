# 简听

面向 HarmonyOS 6.0 及以上手机的本地优先听书与小说阅读 App。在线内容由用户导入的书源提供，规则在设备端执行；支持本地音频导入、章节下载、书架、收听记录、阅读设置、系统媒体控制与桌面播放卡片。`server/` 是可选独立聚合服务和运维后台，App 没有服务器地址配置入口。

本文描述当前代码，页面行为见 [docs/APP_UI.md](docs/APP_UI.md)，开发约束见 [AGENTS.md](AGENTS.md)，服务端使用见 [server/README.md](server/README.md)。

面向书源作者的格式、规则语法与完整示例见 [docs/BOOK_SOURCE_RULES.md](docs/BOOK_SOURCE_RULES.md)。

## 技术基线

- 最低 HarmonyOS 6.0 / API 20；`compatibleSdkVersion = 6.0.0(20)`，目标 HarmonyOS 6.1.1 / API 24，`targetSdkVersion = 6.1.1(24)`。主工程 default / release 与 QuickJS HAR 的最低版本一致。
- `PlatformCompat` 按设备 API 分流：API 23 起启用 HDS 浮动底栏和媒体离线缓存，API 26 起启用正式版 `uiMaterial` 沉浸光感、媒体中心增强控制和浮动导航避让；较新系统模块延迟加载。API 20–22 使用固定底栏及独立迷你播放器，封面预下载通过下载信息轮询完成；API 20–25 的材质使用五档磨砂回退。
- 编译使用经确认的 Release SDK；当前配套为 DevEco Studio 26.0.0.821，编译版本与目标/最低版本分开管理。上传前检查 APP 内所有 HAP 的 `apiReleaseType = Release`，QuickJS HAR 也需用正式工具链重建。
- Stage 模式，单模块 `entry/`，设备类型仅 `phone`。
- ArkTS + ArkUI V2；页面使用 `@Local` 和 Service 单例。
- `bundleName = com.huan.listenbook`；当前 `versionName = 0.1.23`、`versionCode = 1000023`，以 `AppScope/app.json5` 为准。
- 后台模式为 `audioPlayback`、`dataTransfer`，权限包括网络、振动和长时后台运行。
- `entry/libs/quickjs.har` 为 arm64-v8a / x86_64 双 ABI 本地依赖；源码和构建脚本在 `third_party/quickjs/`、`scripts/build-quickjs.ps1`。
- 签名在本机 DevEco Studio 配置，`build-profile.json5` 含私有签名信息，禁止提交其中的本机改动。

## 页面、服务与数据

| 页面 / 流程 | 服务入口 | 数据 |
|---|---|---|
| 首页推荐、分类、更多 | `HomePage` → `HomeSourceService` / `BlockMorePage` → `BookSourceService` | 已选择、启用且支持发现的小说或有声书源，选择保存在本地偏好中 |
| 搜索和搜索推荐 | `SearchPage` → `SourceDataService` → `BookSourceService` | 已启用且具备搜索规则的导入源、`SearchCache`、本地搜索历史 |
| 详情、目录 | `BookDetailPage` → `BookSourceService` → 对应分发器 | `Book`、`Chapter`、书籍索引和按书拆分的目录缓存 |
| 小说阅读 | `ReaderPage` → `BookSourceService`、`OnlineTextPaginator` | 章节正文缓存、字符位置、阅读设置 |
| 播放、下载、导出 | `AudioService`、`AVSessionService`、`DownloadService`、`DownloadExportService` | 音频 URL / Header、播放进度、沙箱音频和导出副本 |
| 书源管理 | `RuleSourcePage` → 导入解析器、仓库、批量测试器 | 加密 `rule_sources.db` |
| 主账号、子源、网页登录 | `RuleSourceAccountPage` / `RuleSourceChildrenPage` / `RuleSourceLoginPage` | 来源主会话、按来源和站点隔离的 Cookie |
| 书架、记录、未收藏历史 | `FavoritePage` / `ReadingStatsPage` / `UnfavoritedHistoryPage` → `PreferenceService`、`StatsService` | 收藏、收听历史、累计统计和播放位置 |
| 本地文件导入 | `ImportPage` → `LocalBookImportService` / `DataService` | 音频、TXT/EPUB/HTML/HTM、ZIP，独立目录及沙箱正文 |
| 系统备份、跨设备续播 | `AppBackupService`、`ContinuationService` | 白名单备份快照、最小播放迁移载荷 |

章节顺序以 PreferenceService 的每书偏好为准，展示目录、播放/朗读上下章及自动续章、阅读跨章和后续章节下载统一跟随；保留原始章节索引和已保存进度。

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
- 书源管理顶部和首页搜索框右侧的独立下拉标签均可设置首页源，共用 `HomeSourceService` 的来源筛选与保存逻辑，仅列已启用的听书源。首页标签按源名称自适应宽度，文字跟随主题色。首页使用保存的源 URL；未设置或原源禁用、删除后，优先选取有首页内容的可用听书源，无听书源时清空内容。默认选中精品推荐，源分类读取所选源的发现定义并保留返回顺序；通用源通过前四个分类生成推荐预览，听友继续使用已有协议获取推荐。未提供或未启用发现的通用源显示提示，仍可搜索。
- 搜索页推荐使用来源真实返回的书籍，优先尝试首页板块，不足时从来源搜索结果补充，再去重随机抽取最多 5 本。
- 首页“分类”入口固定在第一位，提供当前源全部分类的双列卡片总览，复用 `HomeSourceService` 返回的分类与现有分类书单加载方法。右侧“精品推荐”和源分类 Tab 共同横向滚动，默认选中精品推荐；点击总览卡片同步切换书单并定位对应 Tab，分类总览按行懒加载。
- 首页外层导航的滚动模糊与背景材质仅在轮播存在且分类栏尚未吸顶时启用；无轮播或已吸顶时，由内层导航模糊列表背景，防止外层模糊覆盖分类标签、选中标记和折叠搜索按钮。
- 返回精品推荐时，最近更新 Swiper 按三条一页懒加载，横向推荐 List 按书籍懒加载，两者只预加载相邻一项，外层推荐列表只预加载相邻一个板块。`HomeRecommendationDataSource` 在推荐数据返回时更新，跨入口切换保留实例与分页结果；完整收起后的展开先提交布局准备帧，再通过 API 12 的 FrameCallback.onIdle 启动原生弹簧，避免首帧同步创建整组封面；反向点击或页面销毁使旧准备回调失效。
- 推荐与分类列表共用现有内容构建函数，各自使用 Scroller，并绑定到同一内层 HdsNavigation；隐藏推荐列表时保留可见节点，返回时只恢复显隐，避免首屏书卡重新创建和封面解码。隐藏列表停止绘制与点击，父子回顶逻辑按当前入口选择控制器；横向书单跨入口切换保留浏览位置。
- 首页推荐与分类切换时，轮播、分类栏和书单随完整尺寸的内层 HdsNavigation 整体位移；标题栏配置高度和内部占位保持固定，使用原生 animateTo 临界阻尼弹簧（response 0.32、dampingFraction 1）更新 translate 与轮播透明度，快速反向切换继承当前位置和速度。动画结束后只回收一次外层滚动占位，旧回调由序号隔离；过渡期间暂停父子滚动、下拉刷新及自动轮播，分类标签仍可连续点击。整体位移期间不叠加书单与总览卡片入场；其他分类切换保留内容淡入和标签定位，后续可见卡片保留按行限制的交错动画。轮播不声明固定索引，可见性引起的自动播放暂停/恢复保留当前页，数据重置时才通过控制器回到首张；吸顶前最后 64vp 连同阴影淡出，搜索框在自身滚动行程结束后隐藏，避免封面底边和搜索框停留在透明状态栏内。首次加载骨架与真实轮播共用几何计算，推荐骨架与真实内容保持标题、书籍行和页面间距一致。
- 精品推荐页在搜索栏下、分类栏上通过 `HomeCoverCarousel` 展示当前源最多 6 本去重音频封面，复用推荐数据与详情路由；原生 Swiper 提供自动/手动轮播，以滑动进度驱动封面的四角投影，两侧按约 55° 水平压缩呈向内收拢的梯形透视，外沿较高、内沿较短，按可用宽度约束两侧位置以完整保留外沿。透视使用 API 20 的 `transform3D`，背景透明，不再额外展示底部书名，书名保留在封面无障碍说明中。搜索、轮播和分类 Tab 共用同一个外层 Scroll 的位移，搜索前景同步滚动位移，视口 HdsNavigation 在搜索完全移出后收起标题区域，轮播与 Tab 随内容中的 HdsNavigation 等距上移，三者相对位置不变；Tab 到状态栏下方吸顶后，内层 List 才开始滚动，下滑先回列表顶部再展开头部。轮播与 Tab 保留在 bottomBuilder 内，搜索保留在视口标题栏的 stackBuilder 前景中以正常接收点击，使用原生沉浸光感；滚动不改变标题区域尺寸或裁剪轮播，API 26 起通过 BuilderOptions.updated=false 保留节点，旧系统沿用固定构建函数。固定视口的外层 HdsNavigation 提供轮播经过顶部时的原生渐变模糊，吸顶后的内容模糊由内层标题栏响应列表滚动；没有手工状态栏底色遮罩。Refresh 位于父子滚动容器外，下拉跟随比例固定为 0.5，内容位移达到 96vp（手指约 192vp）后松手刷新，请求入口再次校验位移。Tab 下方的主题色指示器在拖动时显示距离进度环，真正刷新后才旋转；头部抵消刷新位移，内容单独跟随下拉。轮播使用每张封面独立的 AttributeUpdater 接收原生可见页位置，逐帧仅更新绘制属性，不回写父组件状态或在换页时重置进度；尺寸换算移出帧回调，层级仅在中心封面交接时切换。轮播仅在可见时自动播放，源切换清空内容，刷新重置位置。
- 听友导入源的站点分类地址 `/categories/<typeId>` 通过原生适配转换为 `types/<typeId>/comprehensive/p<page>`；兼容导入源 `/?type=<typeId>&sort=<sort>&page={{page}}` 的查询参数格式，保留排序与页码。支持本站完整地址、相对地址和连续翻页；原有 `types/...` 地址保留其排序与页码，外部域名不参与此转换。
- 启动流程不调用 `registerBuiltInSources()`，`BookSourceService` 不调用 `BuiltInDispatcher`，搜索页不启动 `KkBiqugeTextSource` 独立任务。相关实现和验证页面仍在仓库，但不代表当前产品入口；`service/builtin/` 中仍有被引用的公共工具，不能按目录整体删除。

### 导入与测试

- 支持本地 `.json`、粘贴 JSON、数组或常见列表外壳、HTTP(S) 导入地址；单次最多 1000 个来源，导入正文上限 10 MiB，单源落库上限 512 KiB。系统“使用其他应用打开”通过 `viewData` + JSON `type` + `FileOpen` 匹配简听，冷启动及 `onNewWant` 均路由至现有书源导入流程。
- 接收结构化规则和 `@{...}` 紧凑规则，保存来源类型、登录定义、`jsLib`、变量和规则字段。
- `LocalRuleSourceCodec` 将编辑字段合并回原始定义，保留扩展字段及未改动的紧凑规则；编辑器提供发现、登录、完整 JSON 校验与单源导出，保存后清理来源列表缓存。
- 书源管理支持分组筛选与维护、批量分组与导出、搜索和发现独立启停、置顶及手动排序。逗号、中文逗号、中点或竖线分隔的多组定义按独立组名筛选，重命名或删除一组保留其他组。锁定状态在数据库事务中保护编辑、重导、分组、启停和删除；测试、置顶、排序与解锁仍可执行。批量操作和全局分组变更跳过锁定来源，重导保留已有本机管理状态。
- 导入后标记“待测试”，保留能力提示和来源启用设置。不能依据漫画、未知类型、脚本登录字段或提示信息推断来源已被禁用；当前非音频类型尝试通用文本内容链，这不等于已有漫画阅读器。
- 单源测试由 `BookSourceService.testLocalSource()` 执行：普通来源有搜索结果时继续验证详情、目录和正文或音频解析；正常请求但无结果时保留来源并给出说明。
- 光遇单源测试确认小说和听书搜索，只执行听书内容链验证；书山验证小说与听书内容链。需要主账号的来源先进入账号页。
- 批量校验提供搜索与发现/阅读两种模式，最多 6 个并发任务。搜索模式调用 `testLocalSourceAvailability()`；发现/阅读模式通过已启用的发现分类抽样验证详情、目录和免费章节内容，空发现或无可验证章节不报成功。可选全部、当前筛选或已选来源，搜索关键词可编辑。取消停止后续调度，未完成来源保留原测试状态；失败默认保留，禁用或删除需用户确认。
- 批量启停和删除使用 400 条谓词分块及事务；同 URL 重导保留主会话和 Cookie，删除则清理对应凭据。

### 规则执行与账号边界

- 请求经 `LocalRuleHttpClient`，支持 HTTP(S)、GET/POST/PUT/PATCH/DELETE/HEAD、Header、编码、有限重试、变量模板和隔离 Cookie。重定向最多 5 次，跨域删除敏感请求头；脚本 response 可读取非 2xx 正文、状态和大小写无关的 Header。`data:` 支持百分号/Base64 内容，发出网络请求需显式 request 选项。
- 证书信任由用户在书源管理中明确添加和撤销，使用独立本机 Preferences 保存 HTTPS 精确主机；不继承子域，不随书源导出或备份迁移。HTTP 每次重定向重新判定主机，例外连接使用独立会话并及时关闭，网页会话重新加载时清理 SSL 缓存。系统证书校验仍是默认行为。
- `LocalRuleStageExtractor` 处理 JSONPath、CSS、XPath、正则、正文净化及组合规则；支持相对 JSON 路径、尾部 `@put`、JS 字段模板和脚本数组后续选择器。JSON 请求体按字段替换模板，保留关键词中的引号和反斜线。
- 请求选项、Header 和发现/登录面板中的宽松 JSON 由 `LocalRuleJsonLiteral` 解析，接受单引号、未加引号的字段名、注释和尾逗号；只接受字面量，不执行函数或表达式，并限制输入、嵌套和节点数。这不代表所有书源导入文件都接受任意 JavaScript 语法。
- `@js` / `jsLib` 经 `LocalRuleScriptRuntime` → `LocalRuleQuickJsRuntime.execute()` → taskpool → native `evaluateBounded`。每次创建独立 context，在 `finally` 释放；默认 1000 ms、64 MiB heap、256 KiB stack，并限制 pending jobs 与输入输出。
- 脚本不能直接访问平台、文件、数据库或不受控网络；`java.ajax` 等兼容网络动作通过原生 HTTP 请求与结果回放完成。
- `LocalRuleScriptCompat` 提供二进制 Base64/Hex、表单编码、Java 字符串和集合白名单、摘要/HMAC/AES、繁简转换、章节数字及时间格式。动作最多 64 次，其中网络最多 32 次；Date 与随机数在重放中稳定，显式 sleep 推进确定性时间，普通规则累计等待最多 10 秒。来源声明的远程 `jsLib` 最多 8 个、合计 2 MiB，按来源和会话隔离缓存 5 分钟。
- 导入书源的 DES/3DES 旧协议通过固定版本 CryptoJS 4.2.0 子集在受限 QuickJS 内执行，支持 CBC/ECB、NoPadding 和 PKCS5/PKCS7，并校验密钥、IV、分块和填充；提供 `createSymmetricCrypto`、Java `Cipher` 与常见 AES/DES Base64 helper。该兼容能力不用于应用数据库、账号、Cookie 或传输加密，不放宽平台加密配置。许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
- `source.getVariable/setVariable`、`source.get/put`、有期限的 `cache` 和登录信息/请求头存入加密 `rule_source_script_state`。同来源脚本串行提交状态，失败脚本不提交；不同来源隔离，网络重放不会重复累加持久化状态。
- 会话 helper 包括登录信息/请求头 Map、按键读取和更新登录信息、移除登录状态，以及保留对象/数字/布尔值的 `source`、`cache` 和任务变量读写。`getLoginHeaderMap()` 对已过期或临近过期的 Bearer JWT 返回空；设备标识和浏览器别名仍通过既有受限动作提供，不暴露新的平台对象。
- JS 章节地址由 `LocalRuleChapterRequest` 延迟至打开章节时执行；稳定章节 URL 携带有界元素上下文，支持重新进入后的请求重建和时效签名刷新。
- `LocalRulePanelService` 解析通用发现与登录表单、嵌套分组及选项标签/值；纯脚本分类入口执行动作，返回书单地址时进入列表，搜索或按钮动作先提交输入规则。登录按钮可调用 `loginUrl` 中的函数，网页动作进入 HTTPS 登录路由。`ruleExplore` 通过现有导入源分发器执行，缺少必要规则时回退搜索规则；听友分类兼容本站完整 URL、相对路径与分页模板。首页通过 `HomeSourceService` 读取所选小说或有声书源的分类和推荐；不自动触发发现面板中的登录、按钮等交互动作。
- 聚合脚本的公共函数在独立 QuickJS 全局上下文中声明，支持 `this.helper()`，不同执行之间不共享函数。JSON 字段脚本提供可读取属性的 `result`，同时保留 `JSON.parse(result)` 兼容；带非空自定义 `type` 的 `data:` 返回原始字节的十六进制文本，普通 `data:` 仍返回解码文本，`type: request` 仍须显式声明网络请求。
- `LocalRuleDebugService` 提供真实阶段及全链路调试、取消检查和脱敏诊断。`concurrentRate` 兼容空值/0（不限流）、正整数（请求间隔毫秒）、负整数（同时请求数）和次数/毫秒窗口；无法识别的可选配置仅记诊断，不阻断请求，并发名额在请求结束后释放。声明式 `session` 可将当前 URL 查询参数映射为 Cookie、生成稳定设备 Cookie 并设置 Referer，状态仍按来源和目标站点隔离。
- 普通 DOM 宿主只解析已下载 HTML；显式 `webView` 使用独立隐私 ArkWeb 渲染网站脚本，主文档由原生响应提供，避免重复提交 POST。限制 128 个资源请求、16 个站点、5 次导航和总时限，退出清空网页会话。`webJs` 在 QuickJS 中通过有序动作读取活动 DOM、输入、点击、分发事件、提交表单、滚动及 HTTP(S) 跳转；同一次动作重放不会重复操作页面，跨页面元素句柄失效。支持有预算的定时回调和 Promise/async 返回值，单次等待最多 10 秒，网页操作和取快照均受总时限约束。`bodyJs` 仍只转换当前响应。外来脚本不会被传给 ArkWeb 执行，也没有网页到平台的 JS 桥。
- Android/Java 数据兼容类包括集合与排序/迭代、Pattern/Matcher、精确 BigInteger/Long、JSONObject/JSONArray、字符集/Base64、内存字节流、GZIP/zlib、CRC32、URI/URL、日期格式、MessageDigest/Mac/Cipher、RSA KeyFactory/Signature 与编码密钥规格。`Java.type`、`Packages`、`importClass/importPackage` 和 `JavaImporter` 只解析显式注册的类；内存流不等于文件访问。每类按已实现的方法执行，未实现的类或操作明确报错，不通过空实现伪装成功。漫画不在当前适配范围内。
- 网页音频嗅探使用资源 URL 和 audio/video/source 节点，并应用 `sourceRegex`。音频规则返回的 URL 选项拆分为实际播放地址与请求头；错误文字不能作为相对音频地址报告成功。
- `RuleSourceLoginPage` 提供 HTTPS 隐私 WebView，不暴露平台桥接；Web 挂载后恢复 Cookie，再加载网站，恢复失败不继续无会话加载。站点 Cookie 按 `source_url + origin` 回写加密数据库，读取失败不覆盖旧值；普通网站登录完成时执行配置的登录检查，等待式登录则将 HTML 返回原脚本继续处理。登录页与网页渲染通过 `LocalRuleWebSession` 互斥使用隐私 Cookie，退出时先完成回写，再清空并释放 Web 会话。
- `java.startBrowserAwait()` 通过 `LocalRuleBrowserLoginCoordinator` 打开可见 HTTPS 登录页，等待用户完成后返回 HTML，再继续原脚本。带 HTML 或脚本的 `java.showBrowser()` 先执行有界网页渲染/DOM 动作，再展示结果等待完成；只传地址时沿用普通打开浏览器行为。等待任务最多一个、默认 120 秒，HTML 输入输出上限 512 KiB；取消、超时或关闭页面会结束等待并释放网页会话。脚本字符串不直接注入网页平台环境，Cookie 写回完成后才恢复等待方。
- 光遇、书山主账号通过 `RuleSourceAccountService` 分发到各自原生账号服务；主会话与子源网站 Cookie 独立保存。
- 当前只实现 Legado/Reader 的兼容子集，导入成功和批量搜索通过均不保证每个来源的完整内容链可用。

## Talebook NAS 导入源

- Talebook 外部 JSON 字段必须同步保留在 `obfuscation-rules.txt`，避免 Release 属性混淆破坏接口解析。

- “书源 → 导入 → 添加 Talebook NAS”输入 HTTP(S) 根地址和可选访问码，验证 `/api/welcome` 与 `/api/user/info` 后添加阅读、听书两个来源；不包含任何预置 NAS 地址或访问码。来源以 `/#talebook-text`、`/#talebook-audio` 标记，由 `NativeRuleSourceDispatcher` 分发，发现列表沿用 `LocalRuleDispatcher` 入口。
- 访问码只用于验证请求；`invited` Cookie 分别按来源和 origin 存入现有加密 Cookie 表，定义导出及备份不携带会话。来源的“登录”可更新过期会话；重新连接不改变已安装定义、启用/锁定状态。当前使用访问码和站点访客权限，不支持 Talebook 用户账号登录及验证码挑战。
- 阅读通过 NAS 的 `/get/extract/{id}/` 获取 EPUB container、OPF spine 和文字正文，按 spine 顺序进入现有在线分页、缓存和进度链；不执行书内脚本、不加载外站资源。TXT 作为单章读取并沿用 HTTP 响应上限（4 Mi 字符），PDF、漫画和服务端格式转换不在本次范围。EPUB 图片和复杂排版不保留。
- 听书读取已发布书单与 manifest，将章节 MP3 和来源 Cookie 交给现有播放/下载链。首页仍只允许选择听书源。请求保持同一 NAS，不使用 App 云 API 或 IPv4/IPv6 中转；仅 IPv6 的 NAS 要求设备网络可达。
- 回归：`node scripts/test-talebook.cjs`（`DEVECO_HOME` 指向 IDE）；可使用 `--live` 加 `TALEBOOK_URL`、`TALEBOOK_CODE`、`TALEBOOK_KEYWORD` 验证授权 NAS，凭据仅从环境读取，不写文件。该主机测试不替代设备上的播放、恢复、下载及导出验证。

## 阅读与播放

- 在线小说用 `OnlineTextPaginator` 分页，按章节标题或索引及 `charOffset` 恢复位置；切换字号和窗口尺寸后重新分页。阅读入口先恢复本地目录，缺失才联网并保存目录。章节正文有内存缓存、请求合并和相邻章节预取；已读和预读正文经 `OnlineTextContentCache` 写入 `cache/online_text_content`，按书源、书籍及章节地址隔离，重启后先读本地，缺失或损坏才联网。缓存随系统/用户清理失效，不代表已下载全书；单章缓存上限 8 MiB，写入失败不阻断阅读。
- 分页前为每个非空正文段落统一添加两个全角空格，测量与显示共用排版文本；页起止偏移映射回清洗后的原文，新增缩进不改变阅读进度的字符坐标。跨页续行不补缩进，正文段落不做启发式合并。
- `ReaderPage` 还保留已有 EPUB 路径的 ReaderKit 分支及 `EpubReaderComponent`；`ImportPage` 已支持音频、TXT/EPUB/HTML/HTM 与 ZIP 批量导入；新导入电子书转为文字章节使用现有阅读器，尚无书签管理入口。
- 阅读页始终隐藏系统状态栏，默认隐藏“详情 / 章节 / 设置”悬浮栏；工具栏与弹层覆盖正文，不改变分页视口。离开阅读路由恢复系统栏，返回时再次隐藏。阅读设置包括字号、行高、翻页方式、羊皮纸／护眼绿／夜间主题和自定义图片主题，支持更换图片及调整蒙层；旧纯白、纯黑、纹理与自定义色设置按兼容规则迁移。页脚默认显示电量与时间，开关独立持久化，不触发重新分页；阅读设置和章节弹层使用固定厚材质及旧系统厚磨砂回退。
- AVPlayer 负责播放、音频焦点和续播，`AVSessionService` 对接系统倍速、上下集和收藏，后台任务维持收听。
- 耳机摘戴通过 AVPlayer 的 `audioOutputDeviceChangeWithInfo` 与 AVSession 播控适配：旧输出设备不可用时暂停并取消焦点自动恢复，加载完成也保持暂停；支持佩戴检测的耳机/系统下发 `play` 后按原进度续播。重复 `play`/`pause` 保持各自语义，设备重新连接本身不触发播放。
- 设置的“启动”分组提供“打开软件自动播放”，默认关闭并随通用设置备份。开启后，冷启动完成播放状态恢复且进入前台时尝试续播上次章节和进度；没有可恢复内容时不播放，普通后台返回不重复起播，跨设备续播及卡片控制优先。
- 播放页支持 0.5x–3.0x 倍速、片头片尾跳过、睡眠定时和 HTTP(S) URL 投播。定时支持按时长（15/30/45/60 分钟、自定义 1–1440 分钟）或按章节（本章、3/5/7 章、自定义最多 999 章且不超过目录剩余数），预设点选、自定义键盘完成后立即生效。章数包含当前章，按目录顺序播放，停止先于续播/循环，片尾跳过计为章末；手动暂停保留、手动切章切书取消章节停止。智能停止仅在到时仍在播放且本章剩余时长大于 0、不超过 10 分钟时等待章节结束，可取消等待，切换开关不重置倒计时。
- 在线 `MediaSource` 系统缓存与用户主动章节下载分开；下载文件可经系统文件选择器导出副本。
- 迷你播放器封面和完整播放页封面保持静止，迷你播放器外圈展示当前集进度。

## 本地存储

| 存储 | 内容 |
|---|---|
| `rule_sources.db` / `rule_sources` | 来源地址、名称、类型、多组、规则 JSON、搜索/发现启用、锁定、置顶、测试状态与自定义排序 |
| `rule_sources.db` / `rule_source_groups` | 手动创建或分配的独立组名；分组删除不删除来源 |
| `rule_sources.db` / `rule_source_sessions` | 按 `source_url` 保存主会话 token、device ID、账号标签 |
| `rule_sources.db` / `rule_source_cookies` | 按 `source_url + origin` 保存站点 Cookie |
| `rule_sources.db` / `rule_source_script_state` | 按来源隔离的脚本变量、缓存、登录信息和登录请求头 |
| `local_rule_tls_trust` Preferences | 本机明确确认的 HTTPS 精确主机证书例外 |
| `PreferenceService`、`PlaybackStore`、`StatsService` | 收藏、收听历史、播放快照、章节进度、统计和通用设置；搜索历史最多 20 条 |
| `online_text_reading_progress` Preferences | 按书保存章节、DOM/字符位置、页偏移和章节标题 |
| `text_reading_settings` Preferences | 字号、行高、主题、翻页方式、背景配置 |
| `DataService` | `cached_books_v1.json` 书籍索引、拆分目录和本地导入书 |
| `files/reader_bg` | 用户选择的阅读背景图片副本 |
| `files/backup/listenbook_state.json` | 系统备份白名单快照 |

`StatsService` 将已恢复的收听统计保留在服务缓存中，计时、删除、清空和恢复操作串行写入 `listenbook_stats` Preferences 与 `files/listening_stats_v3.json` 独立快照。文件通过临时文件、fsync 和重命名替换，启动时按修订号选取有效数据；两份数据均读取失败时不允许按空记录覆盖。旧统计自动迁移，累计时长独立于每日明细保留窗口，跨天与重启不归零。记录页的顶部摘要先于书籍明细更新，明细失败不阻断累计展示。

规则数据库使用 S2 安全级别和加密。备份迁移在线收藏、收听记录和播放进度、统计、通用设置、书籍元数据及清洗后的书源定义；不迁移实际登录会话、Cookie、敏感 Header Token、原始书源 JSON、下载音频及本地导入文件。来源恢复后回到“待测试”。独立阅读 Preferences 不在当前 `AppBackupService` 快照中。

跨设备迁移携带在线书当前章节、原始章节地址、进度、时长、倍速和播放状态，目标设备再补齐目录；不是全量文件或书源账号同步。

### 电子书离线朗读

在线小说阅读页提供系统 CoreSpeechKit 离线 TTS，`TextToSpeechService` 独立于页面生命周期，支持按句播放、0.5–2 倍语速、查询/下载/切换音色、跨章预取、逐字高亮与正文翻页跟随、定时停止及读完本章停止。退出阅读页后可通过首页迷你朗读栏、锁屏和耳机继续控制；焦点丢失或耳机断开时暂停，不自动恢复外放。EPUB 的 ReaderKit 分支暂不接入朗读。

朗读复用导入源正文与 `OnlineTextContentCache`，没有新增服务端或内置内容源。`text_to_speech` Preferences 独立保存设置与按书的来源、章节 URL、字符位置；目录重排按 URL 恢复，暂停从当前句起读。阅读翻页不覆盖朗读进度。朗读尚不生成可下载/导出的音频文件，不提供时间轴拖动或远程投播。

`PlaybackCoordinator` 保证朗读与原有音频互斥，`AVSessionService` 根据当前播放类型切换系统回调并屏蔽旧播放器更新；后台音频任务分别记录 audio/speech 持有者。仅实际播报阶段计入 `StatsService` 收听统计。系统 TTS 在独立进程播放，应用音频会话的空闲超时不视为抢占；真正的焦点抢占仍暂停。逐字游标按句内权重估算并以实际句子播放时长校准，后台不刷新高频游标。此独立 Preferences 暂未加入系统备份白名单。

回归命令：`node scripts/test-text-to-speech.cjs`（`DEVECO_HOME` 指向已安装 IDE），运行真实服务并模拟语音、存储与焦点回调，覆盖分句偏移、跨章、暂停/恢复、旧回调、目录重排、异步取消、互斥、耳机断开、缓存和语速。

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

鸿蒙技能统一按 [AGENTS.md 的在线技能路由](AGENTS.md#online-harmonyos-skill-routing) 使用：每项新任务查询在线索引和目录，按需求读取仓库中的对应技能及必要参考资料；包含嵌套技能和后续新增技能，不在项目中保留整套鸿蒙技能副本。

1. 修改 `.ets` 前在线读取适用的 ArkTS 语法与 ArkUI 技能，遵循 [AGENTS.md](AGENTS.md) 的最低 API 20、目标 API 24 / ArkUI V2 约束。
2. 对修改文件运行 `arkts_check` 或现有工具对应的 `check_ets_files`，再运行 `build_project` 增量构建；成功后用 `start_app` 真机或模拟器验证。发生 ArkTS 错误先在线读取对应的编译修复技能。
3. 工具不可用时使用 `ohpm install`、`hvigorw assembleHap --mode module -p product=default`；`release` 产品用于发布配置。只在确认缓存问题时清理构建。
4. App 单测位于 `entry/src/test/`，涵盖本地规则、原生适配、批量测试、搜索缓存与历史、在线分页、阅读主题、播放进度和下载策略；设备测试位于 `entry/src/ohosTest/ets/test/`。
   - 播控事件回归：`DEVECO_HOME` 指向已安装 IDE 后运行 `node scripts/test-audio-commands.cjs`，以模拟平台事件执行真实 `AudioService`，覆盖耳机摘下、AVSession 重复指令、加载中暂停和迟到焦点恢复；实际佩戴检测仍需耳机真机验证。
   - 书源回归设备类：`LocalRuleCompatibility,LocalRuleFeatures,LocalRuleRuntime,LocalRulePersistence,LocalRuleRequestLimiter`。HTTP/网页集成另启动 `node scripts/local-rule-http-fixture.cjs`，用 HDC 映射 `rport tcp:18997 tcp:18997`，运行 `LocalRuleBrowserIntegration` 并传入 `-s fixtureUrl http://127.0.0.1:18997`；结束后停止服务并移除该映射。
   - `LocalRuleImportedSmoke` 仅在显式传入 `sourceUrl` 时访问实际来源，可用 `importUrl` 临时导入缺失定义，完成后清理临时来源。`SourcePlaybackSmoke` 的 `playbackImportUrl`、`playbackSourceUrl`、`playbackKeyword` 参数覆盖搜索到实际起播和暂停续播，设备测试静音播放。
5. 服务端校验使用 `npm run typecheck`、`npm test`、`npm run build:all`；部署细节见 `server/README.md`。

来源与阅读改动应验证“无导入源空态 → 导入 → 单源/批量测试 → 搜索 → 详情 → 阅读或播放”，以及禁用后的收藏解析、单源失败隔离。播放与下载改动应验证切章、续播、系统控制、下载和导出。UI 改动按 `docs/APP_UI.md` 回归。

华为账号入口当前由 `ENABLE_HW_LOGIN = false` 关闭，模块中的 `client_id` 仍为占位配置。不要将它描述为已上线登录功能。

产品或交互变化直接更新现行文档；已失效的一次性计划和修复说明删除，历史由 Git 保留。

### 本地导入容量与格式

- 音频支持 MP3/M4A/FLAC/WAV/OGG/AAC，电子书支持 TXT/EPUB/HTML/HTM；ZIP 中音频自然排序成书，电子书逐本入架。每次文件选择上限 500，可继续追加。
- 单 ZIP 处理上限 32 GiB、解压内容 64 GiB，包内最多 100000 个文件/目录、50000 个可导入文件；单书最多 50000 章/集。导入前校验剩余空间并保留 256 MiB，多 ZIP 顺序解压并逐包清理。容量为代码上限，不代表已做同等体积设备压力验证。
- TXT 最大 256 MiB，64 KiB 流式解码 UTF-8/UTF-16/GB18030，识别章节标题并限制正文片段长度；HTML/HTM 最大 32 MiB，EPUB 最大 512 MiB、解压内容最多 2 GiB，使用系统 BookParser 按 spine 提取文字。
- 新导入目录存 filesDir/imported_toc，偏好索引只存书籍元数据；正文存 filesDir/ebooks。读取本地正文限定本书路径，不依赖网络书源；删书同时清理目录和正文。ZIP 音频直接移动入库，大于 500 集时不逐集探测时长，播放后补齐。
