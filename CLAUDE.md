# 简听阅读

面向 HarmonyOS 6.0 及以上手机（含折叠屏）、平板及鸿蒙电脑的本地优先听书与小说阅读 App。全网榜单展示平台公开元数据；正文及音频由用户导入的书源提供，规则在设备端执行；支持本地音频导入、章节下载、书架、阅听记录、阅读设置、系统媒体控制与桌面播放卡片。`server/` 是可选独立聚合服务和运维后台，App 没有服务器地址配置入口。

本文描述当前代码，页面行为见 [docs/APP_UI.md](docs/APP_UI.md)，开发约束见 [AGENTS.md](AGENTS.md)，服务端使用见 [server/README.md](server/README.md)。

面向书源作者的格式、规则语法与完整示例见 [docs/BOOK_SOURCE_RULES.md](docs/BOOK_SOURCE_RULES.md)。

## 技术基线

- 最低 HarmonyOS 6.0 / API 20；`compatibleSdkVersion = 6.0.0(20)`，目标 HarmonyOS 26.0.0 / API 26，`targetSdkVersion = 26.0.0`。主工程 default / release 与 QuickJS HAR 的最低版本一致。
- `PlatformCompat` 按设备 API 分流：API 23 起启用 HDS 浮动底栏和媒体离线缓存，API 26 起启用正式版 `uiMaterial` 沉浸光感、媒体中心增强控制和浮动导航避让；较新系统模块延迟加载。API 20–22 使用固定底栏及独立迷你播放器，封面预下载通过下载信息轮询完成；API 20–25 的材质使用三档磨砂回退。
- 编译使用经确认的 Release SDK；当前配套为 DevEco Studio 26.0.0.821，编译版本与目标/最低版本分开管理。上传前检查 APP 内所有 HAP 的 `apiReleaseType = Release`，QuickJS HAR 也需用正式工具链重建。
- Stage 模式，单模块 `entry/`，设备类型为 `phone`、`tablet`、`2in1`、`wearable`；前三者按实际窗口尺寸适配，标准手表使用独立圆屏页面；多端交互与待验证项目见 `docs/APP_UI.md`。
- ArkTS + ArkUI V2；页面使用 `@Local` 和 Service 单例。
- `bundleName = com.huan.listenbook`；当前 `versionName = 0.1.40`、`versionCode = 1000040`，以 `AppScope/app.json5` 为准。
- 后台模式为 `audioPlayback`、`dataTransfer`，权限包括网络、振动和长时后台运行。
- `entry/libs/quickjs.har` 为 arm64-v8a / x86_64 双 ABI 本地依赖；源码和构建脚本在 `third_party/quickjs/`、`scripts/build-quickjs.ps1`。
- 签名在本机 DevEco Studio 配置，`build-profile.json5` 含私有签名信息，禁止提交其中的本机改动。

## 页面、服务与数据

| 页面 / 流程 | 服务入口 | 数据 |
|---|---|---|
| 主题 / 主题图标 | `AppIconPage` → `AppIconService` → `bundleManager` | 默认图标免费，其余图标需要会员；选择由系统保存；API 26 起切换，API 20–25 仅预览 |
| 我的 / 账号下方 / 会员中心 | `ProfilePage` → `MembershipSubscriptionPage` → `MembershipService` → 华为 IAP Kit | 无自有服务器；`iconMonth` 月订阅、`iconYear` 年订阅、`lastVip` 非消耗型终身会员；主题图标、自动备份和书源不限总数需要会员；非会员恢复默认设置 |
| 全网榜单、平台排行、版本匹配 | `RankingHomePage` → `RankingService` / `BookMatchService` → `BookSourceService` | 公开榜单元数据、独立本地缓存、已启用的导入书源 |
| 首页推荐、分类、更多 | `HomePage` → `HomeSourceService` / `BlockMorePage` → `BookSourceService` | 已选择、启用且支持发现的小说或有声书源，选择保存在本地偏好中 |
| 搜索和搜索推荐 | `SearchPage` → `SourceDataService` → `BookSourceService` | 已启用且具备搜索规则的导入源、`SearchCache`、本地搜索历史 |
| 详情、目录 | `BookDetailPage` → `BookSourceService` → 对应分发器 | `Book`、`Chapter`、书籍索引和按书拆分的目录缓存 |
| 小说阅读 | `ReaderPage` → `BookSourceService`、`OnlineTextPaginator` | 章节正文缓存、字符位置、阅读设置 |
| 播放、下载、导出 | `AudioService`、`AVSessionService`、`DownloadService`、`DownloadExportService` | 音频 URL / Header、播放进度、沙箱音频和导出副本 |
| 书源管理 | `RuleSourcePage` → 导入解析器、仓库、批量测试器 | 加密 `rule_sources.db` |
| 主账号、子源、网页登录 | `RuleSourceAccountPage` / `RuleSourceChildrenPage` / `RuleSourceLoginPage` | 来源主会话、按来源和站点隔离的 Cookie |
| 华为账号登录、退出 | `ProfilePage` → `AuthService` → Account Kit | `listenbook_prefs.hw_account_v1` 保存 UnionID、OpenID、登录时间；前台恢复核对系统账号 |
| 书架、记录、未收藏历史 | `FavoritePage` / `ReadingStatsPage` / `UnfavoritedHistoryPage` → `PreferenceService`、`StatsService`、`TextReadingProgressService` | 收藏、阅听历史、累计收听统计和阅读/播放位置 |
| 本地文件导入 | `ImportPage` → `LocalBookImportService` / `DataService` | 音频、TXT/EPUB/MOBI/HTML/HTM、ZIP，独立目录及沙箱正文 |
| 我的 / 日志管理 | `LogManagementPage` → `DiagnosticLogService` | 本机 `diagnostic_log.json`，默认关闭、日志页可手动开启并保存本机选择；最多 200 条，导入阶段/错误码、启动异常及存储检测；关闭保留历史，可筛选、复制、清空，不上传 |
| 系统备份、跨设备续播 | `AppBackupService`、`ContinuationService` | 白名单备份快照、最小播放迁移载荷 |

章节顺序以 PreferenceService 的每书偏好为准，展示目录、播放/朗读上下章及自动续章、阅读跨章和后续章节下载统一跟随；保留原始章节索引和已保存进度。

封面优先级由 BookCoverPolicy 统一处理：详情规则返回的封面记录 coverFromDetail，并保留 coverFallback；SearchCache、书籍索引写入和详情目录恢复不得用搜索缩略图覆盖已知详情封面。旧记录未带来源标记时不猜测图片质量。播放页 PlayerCoverImage 按容器尺寸解码，确认成功才显示高清层，失败保留备用图。

设置中的“AI 封面超分”默认关闭，仅为播放页低清网络封面调用系统 CoreVisionKit ImageSRAnalyzer（API 26，懒加载并做版本/能力检查）。增强结果独立存放于 cacheDir，最多 12 张，关闭、处理失败或系统不支持时显示原图；不改变书源封面地址或列表封面。

主导航是 `Index` + `NavPathStack`，`MainPage` 承载“首页 / 书架 / 记录 / 我的”。搜索、详情、阅读、播放器、导入、下载和书源管理使用独立路由。

## 会员限制与开发者调试

- 主题图标、自动云备份及周期设置、导入书源不限总数需要会员；非会员最多 8 个书源。会员中心位于账号卡片下方，主题页仅展示图标选择；点击付费图标或自动备份设置进入会员中心，书源超限显示会员提示。
- `MembershipState.active` 仅表示真实验签会员；`hasAccess` 统一检查真实会员或开发者调试豁免。不从备份恢复会员状态。
- 图标切换复用本进程仍有效的已验签权益，不逐次强制联网；会员同步期间禁用切换并显示加载，未知或过期时合并查询。仅确认非会员才打开开通弹框，查询失败显示错误并允许重试，不视为已确认非会员。搜索并发、自动备份及周期设置共用这一核验策略，未知或失败时提供重试，异步核验结束前退出页面不执行设置或导航；会员中心在状态未知时禁用购买并提供重试。
- 会员权益与商品价格并行加载；会员中心、主题及设置入口合并请求，在权益自身的 5 分钟有效窗口内复用已验签会员（订阅到期不复用），确认非会员缓存 60 秒，商品价格缓存 5 分钟，前台恢复、购买和手动恢复强制核验。手动恢复同时刷新价格；价格通过 API 20 的商品 ID 列表重载一次查询月/年/终身套餐；普通核验只查询当前权益并确认当前订单，手动恢复及支付后核对才追加历史未完成订单查询。
- 划掉应用后冷启动及回到前台时，先恢复本机上次验签成功的会员展示（徽标、昵称配色、套餐和到期时间），同时联网核验当前系统账号。展示快照独立保存于 membership_display_v1，最长保留 24 小时且不得越过订阅到期时间，不进入 App 备份、不保存订单或身份令牌；恢复展示绝不恢复 active/hasAccess 或启用购买，真实权益仍使用本进程验签的 5 分钟窗口。查明无权益或核验失败清除内存和磁盘展示，损坏、过期及未来时间缓存忽略；迟到缓存不能覆盖更新的核验结果。
- CURRENT_ENTITLEMENT 确认无有效权益或已核验有效期届满后，恢复系统默认图标，将当前账号本机自动备份关闭、周期恢复每天并持久化。保留备份历史、云端覆盖保护；切换账号后加载其设置时也执行检查。已有超额书源不删除，仍可更新或删除，新增继续受限。
- 无有效会员时恢复默认设置：查询失败或支付服务不可用也关闭自动备份、恢复默认图标及搜索并发 3。等待查询期间不授予权限，开发者调试豁免除外。
- 开发者使用 `entry/src/main/ets/service/membership/DeveloperMembership.ets`：将 `ENABLED` 改为 `true`，构建并安装自己的 debug 包；`applicationInfo.debug` 必须为 true 才放行。默认关闭，正式 release 包即使误开常量也不生效；不伪造订单、会员徽标或购买状态。改回 false 并重新安装可测试普通用户流程。不要把开启豁免的调试包用于普通用户邀测。
- 图标 API 26 能力保护、并发切换保护和系统状态回读保留；自动备份仍需登录、主动开启，并保留前台调度、账号隔离、手动操作优先及失败退避。第三方书源自身的账号和内容授权不受开发者豁免影响。
- 回归：`test-membership.cjs`、`test-auto-backup.cjs`、`test-rule-source-management.cjs`、`test-source-file-import.cjs`。订单按固定信任锚、PKIX/OID/ES256 和订单政策核验。2026-10-09 在 Mate 80（API 26）验证沙盒终身订单恢复、验签和确认发货成功；生产购买、退款及其他设备仍待验证。内置根证书按 PEM 读取，证书公钥须导出后通过 CryptoFramework 重新导入，不能将 Cert 公钥对象直接用于验签初始化。
- 沙盒限制：华为 [queryPurchases 文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/iap-iap) 明确已发货的非消耗型订单不再返回；实机确认发货后再次查询为空时，本应用按当前权益结果取消会员。此行为不能用于判断生产终身会员是否持久有效，也不使用历史订单绕过当前权益核验。

## 应用市场更新

关于页“获取更新”通过 `UpdateService.openAppGallery()` 打开华为应用市场简听阅读详情页（App ID `6917615941058168740`，跳转参数使用包名 `com.huan.listenbook`），失败时尝试官方 HTTPS 页面，全部失败提示手动搜索。版本判断、下载与安装由市场提供；不再启动 GitHub 检查或读取旧版本缓存。

## 内容分发

```text
用户导入 JSON / HTTP(S) 地址
  -> LocalRuleSourceImportParser
  -> LocalRuleSourceRepository (rule_sources.db)
  -> SourceDataService
  -> BookSourceService
       -> NativeRuleSourceDispatcher -> 光遇 / 书山原生适配
       -> LocalRuleDispatcher
            -> 声明式提取 / LocalRuleScriptRuntime / 受控 HTTP
```

- 全网榜单是独立的发现元数据入口，不注册为 `BookSource`，不参与正文、音频、下载分发，也不依赖可选 `server/`。首次使用、无源或保存的首页源失效时默认展示；原书源首页选择菜单可切换“全网榜单”，该模式以 `home://rankings` 保存于原首页偏好，绝不写入书源数据库。
- `RankingService` 提供五个平台各 6 榜，共 30 榜：起点月票、畅销、完结（畅销完本）、阅读、推荐、新书；懒人热播、热评、热搜、免费、畅销、完结周榜；喜马拉雅免费经典、付费畅销、有声书热播、新品、口碑、小说 VIP；七猫男女生大热、新书、完结；晋江总分、月度、季度、半年、VIP 强推、字数。保留官网顺序和实际数量，不虚构跨平台总榜。当前起点、七猫每榜 20 项，懒人 17～20 项，喜马拉雅旧入口 10 项、新入口 95～98 项，晋江 VIP 强推 12 项、其余 100 项；数量随官网变化。起点优先读取结构化记录，完结榜仅接受明确完本状态；分页接口当前不可直接访问，仅展示首批 20 项。喜马拉雅新增入口按 rankId 匹配指定榜单，禁止误用默认推荐合集，相对封面补全官网 HTTPS 图片域名。起点封面使用 600×800、懒人使用 600×600 地址。缓存有效期 6 小时，刷新失败保留带更新时间的旧缓存，超过 30 天不读取；最多三个榜单请求并发，按展示顺序逐榜读取缓存并立即显示，不等待全部 30 榜缓存解析；精品推荐前两项为懒人热播、起点月票，当前平台刷新优先。列表键包含榜单 ID、获取时间及加载状态，避免缓存节点停留在加载中；单榜失败独立呈现。
- `BookMatchService` 只搜索已启用、具备搜索能力的导入源，沿用搜索并发设置；按书名、作者和返回文本中的主播信息排列候选，同时保留电子书和有声书版本，由“全部 / 有声书 / 电子书”分组筛选，用户显式选择后才缓存为真实来源书籍并进入现有详情。最多显示 150 个匹配结果，按来源与书籍 URL 去重。上次选择仅影响优先搜索和排序，每次重新搜索验证；取消后不继续调度、不回写迟到结果。无可用源时支持跳往书源管理，返回后继续匹配。榜单与匹配缓存位于 cacheDir，不加入书架、进度和书源备份。
- `SourceDataService` 只聚合导入源，排除 `builtin://` 地址；数据库读取失败时返回空列表或未找到来源。
- 搜索采用完成一个立即补下一个的并发队列，默认同时搜索 3 个来源；“设置 → 搜索”（位于播放分组下方）提供 3/6/9/12 和 1–12 自定义并发数，持久化并纳入备份，下次提交搜索生效。按 `sourceUrl + bookUrl` 去重；单源失败独立处理，过期搜索停止后续调度且结果不覆盖新搜索。
- 首页推荐按分类完成顺序渐进显示，最终保持源分类顺序；最近 4 个来源的分类与推荐在内存中缓存 5 分钟，同源在途加载合并。下拉刷新绕过缓存，来源定义或登录状态变化使缓存失效，切源后的旧请求不回写当前页面。
- `enabled`、有效来源地址及搜索必需规则共同决定是否参与新搜索。测试状态是诊断信息，不要求先变为“可用”才能搜索。
- 关闭来源不会删除定义，已有收藏仍可按来源解析；删除来源会同时删除主会话、Cookie 和脚本持久化状态，但不删除或隐藏书架、阅听记录、进度和书籍元数据。这些数据仍参与本地/云备份，旧来源不可用时可进入阅读页或播放器换源。
- 首页搜索框右侧的独立下拉标签设置首页源，使用 `HomeSourceService` 的来源筛选与保存逻辑，仅列已启用且支持发现的小说或听书源。首页标签按源名称自适应宽度，文字跟随主题色。首页保留已保存且仍有效的发现源；未设置、选择全网榜单或原源失效后，显示全网榜单首页。默认选中精品推荐，源分类读取所选源的发现定义并保留返回顺序；所有通用源通过源定义的前四个分类生成推荐预览，听友也遵循导入规则，不注入固定分类或专用接口。未提供或未启用发现的通用源显示提示，仍可搜索。
- 搜索页推荐使用来源真实返回的书籍，优先尝试首页板块，不足时从来源搜索结果补充，再去重随机抽取最多 5 本。进入页面优先显示本地搜索历史，不自动弹出键盘；书源推荐避开入场转场加载，提交搜索或隐藏页面时取消待调度的推荐与旧推荐回写。
- 首页“分类”入口固定在第一位，提供当前源全部分类的双列卡片总览，复用 `HomeSourceService` 返回的分类与现有分类书单加载方法。右侧“精品推荐”和源分类 Tab 共同横向滚动，默认选中精品推荐；点击总览卡片同步切换书单并定位对应 Tab，分类总览按行懒加载。
- 首页外层导航的滚动模糊与背景材质仅在轮播存在且分类栏尚未吸顶时启用；无轮播或已吸顶时，由内层导航模糊列表背景，防止外层模糊覆盖分类标签、选中标记和折叠搜索按钮。
- 返回精品推荐时，最近更新 Swiper 按三条一页懒加载，横向推荐 List 按书籍懒加载，两者只预加载相邻一项，外层推荐列表只预加载相邻一个板块。`HomeRecommendationDataSource` 在推荐数据返回时更新，跨入口切换保留实例与分页结果；完整收起后的展开先提交布局准备帧，再通过 API 12 的 FrameCallback.onIdle 启动原生弹簧，避免首帧同步创建整组封面；反向点击或页面销毁使旧准备回调失效。
- 推荐与分类列表共用现有内容构建函数，各自使用 Scroller，并绑定到同一内层 HdsNavigation；隐藏推荐列表时保留可见节点，返回时只恢复显隐，避免首屏书卡重新创建和封面解码。隐藏列表停止绘制与点击，父子回顶逻辑按当前入口选择控制器；横向书单跨入口切换保留浏览位置。
- 首页推荐与分类切换时，轮播、分类栏和书单随完整尺寸的内层 HdsNavigation 整体位移；标题栏配置高度和内部占位保持固定，使用原生 animateTo 临界阻尼弹簧（response 0.32、dampingFraction 1）更新 translate 与轮播透明度，快速反向切换继承当前位置和速度。动画结束后只回收一次外层滚动占位，旧回调由序号隔离；过渡期间暂停父子滚动、下拉刷新及自动轮播，分类标签仍可连续点击。整体位移期间不叠加书单与总览卡片入场；其他分类切换保留内容淡入和标签定位，后续可见卡片保留按行限制的交错动画。轮播不声明固定索引，可见性引起的自动播放暂停/恢复保留当前页，数据重置时才通过控制器回到首张；吸顶前最后 64vp 连同阴影淡出，搜索框在自身滚动行程结束后隐藏，避免封面底边和搜索框停留在透明状态栏内。首次加载骨架与真实轮播共用几何计算，推荐骨架与真实内容保持标题、书籍行和页面间距一致。
- 精品推荐页在搜索栏下、分类栏上通过 `HomeCoverCarousel` 展示当前源最多 6 本去重音频封面，复用推荐数据与详情路由；原生 Swiper 提供自动/手动轮播，以滑动进度驱动封面的四角投影，两侧按约 55° 水平压缩呈向内收拢的梯形透视，外沿较高、内沿较短，按可用宽度约束两侧位置以完整保留外沿。透视使用 API 20 的 `transform3D`，背景透明，不再额外展示底部书名，书名保留在封面无障碍说明中。搜索、轮播和分类 Tab 共用同一个外层 Scroll 的位移，搜索前景同步滚动位移，视口 HdsNavigation 在搜索完全移出后收起标题区域，轮播与 Tab 随内容中的 HdsNavigation 等距上移，三者相对位置不变；Tab 到状态栏下方吸顶后，内层 List 才开始滚动，下滑先回列表顶部再展开头部。轮播与 Tab 保留在 bottomBuilder 内，搜索保留在视口标题栏的 stackBuilder 前景中以正常接收点击，使用原生沉浸光感；滚动不改变标题区域尺寸或裁剪轮播，API 26 起通过 BuilderOptions.updated=false 保留节点，旧系统沿用固定构建函数。固定视口的外层 HdsNavigation 提供轮播经过顶部时的原生渐变模糊，吸顶后的内容模糊由内层标题栏响应列表滚动；没有手工状态栏底色遮罩。Refresh 位于父子滚动容器外，下拉跟随比例固定为 0.5，内容位移达到 96vp（手指约 192vp）后松手刷新，请求入口再次校验位移。Tab 下方的主题色指示器在拖动时显示距离进度环，真正刷新后才旋转；头部抵消刷新位移，内容单独跟随下拉。轮播使用每张封面独立的 AttributeUpdater 接收原生可见页位置，逐帧仅更新绘制属性，不回写父组件状态或在换页时重置进度；尺寸换算移出帧回调，层级仅在中心封面交接时切换。轮播仅在可见时自动播放，源切换清空内容，刷新重置位置。
- 听友的发现、详情、目录和播放均使用导入源的通用规则链路，不再识别域名转入原生协议。源地址、请求头、脚本和分类由用户导入定义决定。
- 听友专用适配、旧内置实现及注册入口已移除。`BookSourceService` 不调用 `BuiltInDispatcher`，搜索页不启动 `KkBiqugeTextSource` 独立任务；`service/builtin/` 中仍有被引用的公共工具，不能按目录整体删除。

### 导入与测试

- 本地文件选择支持多选：每批最多 10 个 JSON，单文件 10 MiB、合计 30 MiB、最多处理 1000 个书源，单源原始 JSON 超过 512 KiB 时跳过。串行读取、taskpool 后台解析、每 8 个模型让出主线程，逐文件落库，结束后统一刷新并汇总跳过数量。
- 支持本地 `.json`、粘贴 JSON、数组或常见列表外壳、HTTP(S) 导入地址；单次最多 1000 个来源，导入正文上限 10 MiB，单源落库上限 512 KiB。系统“使用其他应用打开”通过 `viewData` + JSON `type` + `FileOpen` 匹配简听阅读，冷启动及 `onNewWant` 均路由至现有书源导入流程。
- 接收结构化规则和 `@{...}` 紧凑规则，保存来源类型、登录定义、`jsLib`、变量和规则字段。
- `LocalRuleSourceCodec` 将编辑字段合并回原始定义，保留扩展字段及未改动的紧凑规则；编辑器提供发现、登录、完整 JSON 校验与单源导出，保存后清理来源列表缓存。
- 书源管理支持分组筛选与维护、批量分组与导出、搜索和发现独立启停、置顶及手动排序。逗号、中文逗号、中点或竖线分隔的多组定义按独立组名筛选，重命名或删除一组保留其他组。锁定状态在数据库事务中保护编辑、重导、分组、启停和删除；测试、置顶、排序与解锁仍可执行。批量操作和全局分组变更跳过锁定来源，重导保留已有本机管理状态。
- 导入后标记“待测试”，保留能力提示和来源启用设置。不能依据漫画、未知类型、脚本登录字段或提示信息推断来源已被禁用；当前非音频类型尝试通用文本内容链，这不等于已有漫画阅读器。
- 单源测试由 `BookSourceService.testLocalSource()` 执行：普通来源有搜索结果时继续验证详情、目录和正文或音频解析；正常请求但无结果时保留来源并给出说明。
- 单源和批量搜索校验缺少搜索规则或搜索链路失败时，补测已启用的发现/阅读链路；公开章节内容验证成功后以“部分可用”通过，保留搜索失败原因，双链失败合并原因。补测遵循取消状态，不改变来源启用设置。
- 书源调试页的“全链路”同样支持搜索失败/无结果后从已启用的发现分类取书，再验证详情、目录及公开章节内容；日志和结果保留搜索错误，仅搜索调试不回退，取消不继续请求。
- 光遇单源测试确认小说和听书搜索，只执行听书内容链验证；书山验证小说与听书内容链。需要主账号的来源先进入账号页。
- 批量校验提供搜索与发现/阅读两种模式，最多 6 个并发任务。搜索模式调用 `testLocalSourceAvailability()`；发现/阅读模式通过已启用的发现分类抽样验证详情、目录和免费章节内容，空发现或无可验证章节不报成功。可选全部、当前筛选或已选来源，搜索关键词可编辑。取消停止后续调度，未完成来源保留原测试状态；失败默认保留，禁用或删除需用户确认。
- 批量启停和删除使用 400 条谓词分块及事务；同 URL 重导保留主会话和 Cookie，删除则清理对应凭据。

### 规则执行与账号边界

- 请求经 `LocalRuleHttpClient`，支持 HTTP(S)、GET/POST/PUT/PATCH/DELETE/HEAD、Header、编码、有限重试、变量模板和隔离 Cookie。重定向最多 5 次，跨域删除敏感请求头；脚本 response 可读取非 2xx 正文、状态和大小写无关的 Header。`data:` 支持百分号/Base64 内容，发出网络请求需显式 request 选项。
- 证书信任由用户在书源管理中明确添加和撤销，使用独立本机 Preferences 保存 HTTPS 精确主机；不继承子域，不随书源导出或备份迁移。HTTP 每次重定向重新判定主机，例外连接使用独立会话并及时关闭，网页会话重新加载时清理 SSL 缓存。系统证书校验仍是默认行为。
- 简介在搜索、发现和详情输出时转为纯文本，解码 HTML 实体、清除标签并保留段落换行；详情展示同时兼容旧缓存简介。源返回的字数、最新章节和更新时间贯通书籍及持久缓存，字数不作为目录章节数。详情标签下独立展示最新更新时间，源未返回时隐藏。
- 听书通用链使用 `LocalRuleAudioResolver` 解析嵌套音频结果、转义/相对 URL 和 `sourceRegex`，空规则及纯 `baseUrl` 规则支持无后缀直链；`AudioRequestInfo.resolved` 将显式确认传递到播放、预加载、下载和换源校验。网页嗅探等待匹配媒体而非仅等待 DOM 稳定，跨域仅补回目标 origin 的 Cookie。规则使用 `custom` 时提供按书持久化的书源音色入口，重载保留进度，已下载音频不改写。
- `LocalRuleStageExtractor` 处理 JSONPath、CSS、XPath、正则、正文净化及组合规则；兼容轻页的脚本备选分支、首/后页 URL 分支、CSS 多索引与表格片段，JSON 脚本链保留对象。Java 风格正则通过有界转换器兼容，复杂方言不保证完全等价；支持相对 JSON 路径、尾部 `@put`、JS 字段模板和脚本数组后续选择器。JSON 请求体按字段替换模板，保留关键词中的引号和反斜线。
- 请求选项、Header 和发现/登录面板中的宽松 JSON 由 `LocalRuleJsonLiteral` 解析，接受单引号、未加引号的字段名、注释和尾逗号；只接受字面量，不执行函数或表达式，并限制输入、嵌套和节点数。这不代表所有书源导入文件都接受任意 JavaScript 语法。
- `@js` / `jsLib` 经 `LocalRuleScriptRuntime` → `LocalRuleQuickJsRuntime.execute()` → taskpool → native `evaluateBounded`。每次创建独立 context，在 `finally` 释放；默认 1000 ms、64 MiB heap、256 KiB stack，并限制 pending jobs 与输入输出。
- 脚本不能直接访问平台、文件、数据库或不受控网络；`java.ajax` 等兼容网络动作通过原生 HTTP 请求与结果回放完成。
- `LocalRuleScriptCompat` 提供二进制 Base64/Hex、表单编码、Java 字符串和集合白名单、摘要/HMAC/AES、繁简转换、章节数字及时间格式。动作最多 64 次，其中网络最多 32 次；Date 与随机数在重放中稳定，显式 sleep 推进确定性时间，普通规则累计等待最多 10 秒。来源声明的远程 `jsLib` 最多 8 个、合计 2 MiB，按来源和会话隔离缓存 5 分钟。
- 导入书源的 DES/3DES 旧协议通过固定版本 CryptoJS 4.2.0 子集在受限 QuickJS 内执行，支持 CBC/ECB、NoPadding 和 PKCS5/PKCS7，并校验密钥、IV、分块和填充；提供 `createSymmetricCrypto`、Java `Cipher` 与常见 AES/DES Base64 helper。该兼容能力不用于应用数据库、账号、Cookie 或传输加密，不放宽平台加密配置。许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
- `source.getVariable/setVariable`、`source.get/put`、有期限的 `cache` 和登录信息/请求头存入加密 `rule_source_script_state`。同来源脚本串行提交状态，失败脚本不提交；不同来源隔离，网络重放不会重复累加持久化状态。
- 会话 helper 包括登录信息/请求头 Map、按键读取和更新登录信息、移除登录状态，以及保留对象/数字/布尔值的 `source`、`cache` 和任务变量读写。`getLoginHeaderMap()` 对已过期或临近过期的 Bearer JWT 返回空；设备标识和浏览器别名仍通过既有受限动作提供，不暴露新的平台对象。
- JS 章节地址由 `LocalRuleChapterRequest` 延迟至打开章节时执行；稳定章节 URL 携带有界元素上下文，支持重新进入后的请求重建和时效签名刷新。
- 网页目录和发现列表的静态 DOM 字段每批最多 32 条提取，单批 HTML 不超过 128 Ki 字符、输出不超过 512 Ki 字符；复用同一片段的解析结果，保留脚本和变量规则的原始执行顺序，超预算或解析失败回退逐字段路径。详情页首帧展示搜索/发现缓存；封面转场结束后开始数据加载，优先恢复已存目录，避免无目录的搜索快照遮蔽收藏缓存。转场不等待网络封面加载，窗口坐标包含祖先绘制变换，普通书卡和轮播均通过有时限的异步截图进入。封面动画请求设备支持的 60–120 帧，进入时停止首页绘制，不做双页整页合成渐变，交接后按帧恢复详情背景和标签材质，仅独立氛围层渐显；首页卡片以组件实例 ID 绑定点击封面，推荐板块分批插入后按板块身份判断首板块，避免重复书籍串位；本地目录 JSON 经 ChapterCacheWorker 在 taskpool 解析，避免文件读取完成后继续在 UI 线程解析大目录。
- `LocalRulePanelService` 解析通用发现与登录表单、嵌套分组及选项标签/值；纯脚本分类入口执行动作，返回书单地址时进入列表，搜索或按钮动作先提交输入规则。登录按钮可调用 `loginUrl` 中的函数，网页动作进入 HTTPS 登录路由。`ruleExplore` 通过现有导入源分发器执行，缺少必要规则时回退搜索规则；分类地址按源定义解析相对路径与分页模板。首页通过 `HomeSourceService` 读取所选小说或有声书源的分类和推荐；不自动触发发现面板中的登录、按钮等交互动作。
- 聚合脚本的公共函数在独立 QuickJS 全局上下文中声明，支持 `this.helper()`，不同执行之间不共享函数。JSON 字段脚本提供可读取属性的 `result`，同时保留 `JSON.parse(result)` 兼容；带非空自定义 `type` 的 `data:` 返回原始字节的十六进制文本，普通 `data:` 仍返回解码文本，`type: request` 仍须显式声明网络请求。
- `LocalRuleDebugService` 提供真实阶段及全链路调试、取消检查和脱敏诊断。`concurrentRate` 兼容空值/0（不限流）、正整数（请求间隔毫秒）、负整数（同时请求数）和次数/毫秒窗口；无法识别的可选配置仅记诊断，不阻断请求，并发名额在请求结束后释放。声明式 `session` 可将当前 URL 查询参数映射为 Cookie、生成稳定设备 Cookie 并设置 Referer，状态仍按来源和目标站点隔离。
- 普通 DOM 宿主只解析已下载 HTML；显式 `webView` 使用独立隐私 ArkWeb 渲染网站脚本，主文档由原生响应提供，避免重复提交 POST。限制 128 个资源请求、16 个站点、5 次导航和总时限，退出清空网页会话。`webJs` 在 QuickJS 中通过有序动作读取活动 DOM、输入、点击、分发事件、提交表单、滚动及 HTTP(S) 跳转；同一次动作重放不会重复操作页面，跨页面元素句柄失效。支持有预算的定时回调和 Promise/async 返回值，单次等待最多 10 秒，网页操作和取快照均受总时限约束。`bodyJs` 仍只转换当前响应。外来脚本不会被传给 ArkWeb 执行，也没有网页到平台的 JS 桥。
- Android/Java 数据兼容类包括集合与排序/迭代、Pattern/Matcher、精确 BigInteger/Long、JSONObject/JSONArray、字符集/Base64、内存字节流、GZIP/zlib、CRC32、URI/URL、日期格式、MessageDigest/Mac/Cipher、RSA KeyFactory/Signature 与编码密钥规格。`Java.type`、`Packages`、`importClass/importPackage` 和 `JavaImporter` 只解析显式注册的类；内存流不等于文件访问。每类按已实现的方法执行，未实现的类或操作明确报错，不通过空实现伪装成功。漫画不在当前适配范围内。
- 网页音频嗅探使用资源 URL 和 audio/video/source 节点，并应用 `sourceRegex`。音频规则返回的 URL 选项拆分为实际播放地址与请求头；错误文字不能作为相对音频地址报告成功。
- `RuleSourceLoginPage` 提供 HTTPS 隐私 WebView，不暴露平台桥接；Web 挂载后恢复 Cookie，再加载网站，恢复失败不继续无会话加载。站点 Cookie 按 `source_url + origin` 回写加密数据库，读取失败不覆盖旧值；普通网站登录完成时执行配置的登录检查，等待式登录则将 HTML 返回原脚本继续处理。登录页与网页渲染通过 `LocalRuleWebSession` 互斥使用隐私 Cookie，退出时先完成回写，再清空并释放 Web 会话。
- `java.startBrowserAwait()` 通过 `LocalRuleBrowserLoginCoordinator` 打开可见 HTTPS 登录页，等待用户完成后返回 HTML，再继续原脚本。带 HTML 或脚本的 `java.showBrowser()` 先执行有界网页渲染/DOM 动作，再展示结果等待完成；只传地址时沿用普通打开浏览器行为。等待任务最多一个、默认 120 秒，HTML 输入输出上限 512 KiB；取消、超时或关闭页面会结束等待并释放网页会话。脚本字符串不直接注入网页平台环境，Cookie 写回完成后才恢复等待方。
- 光遇、书山主账号通过 `RuleSourceAccountService` 分发到各自原生账号服务；主会话与子源网站 Cookie 独立保存。
- 光遇 26.9.29 使用 `qingtian618.com` 七条 HTTPS 线路。主账号登录同步到该源的加密 Cookie 仓库，供原始发现/账号脚本使用；退出同时清理这些线路的 Cookie。原生请求读取源变量中的线路、超时、搜索模式/来源、强制搜索和网络模式；发现结果转为 `gy://` 路由，本地网络模式保留上游网页地址，旧路由仍可读取。子书源目录读取服务端配置，不额外执行搜索。
- 当前只实现 Legado/Reader 的兼容子集，导入成功和批量搜索通过均不保证每个来源的完整内容链可用。

## Talebook NAS 导入源

- Talebook 外部 JSON 字段必须同步保留在 `obfuscation-rules.txt`，避免 Release 属性混淆破坏接口解析。

- “书源 → 导入 → 添加 Talebook NAS”输入 HTTP(S) 根地址和可选访问码，验证 `/api/welcome` 与 `/api/user/info` 后添加阅读、听书两个来源；不包含任何预置 NAS 地址或访问码。来源以 `/#talebook-text`、`/#talebook-audio` 标记，由 `NativeRuleSourceDispatcher` 分发，发现列表沿用 `LocalRuleDispatcher` 入口。
- 访问码只用于验证请求；`invited` Cookie 分别按来源和 origin 存入现有加密 Cookie 表，定义导出及备份不携带会话。来源的“登录”可更新过期会话；重新连接不改变已安装定义、启用/锁定状态。当前使用访问码和站点访客权限，不支持 Talebook 用户账号登录及验证码挑战。
- 阅读通过 NAS 的 `/get/extract/{id}/` 获取 EPUB container、OPF spine 和文字正文，按 spine 顺序进入现有在线分页、缓存和进度链；不执行书内脚本、不加载外站资源。TXT 作为单章读取并沿用 HTTP 响应上限（4 Mi 字符），PDF、漫画和服务端格式转换不在本次范围。EPUB 图片和复杂排版不保留。
- 听书读取已发布书单与 manifest，将章节 MP3 和来源 Cookie 交给现有播放/下载链。首页仍只允许选择听书源。请求保持同一 NAS，不使用 App 云 API 或 IPv4/IPv6 中转；仅 IPv6 的 NAS 要求设备网络可达。
- 回归：`node scripts/test-talebook.cjs`（`DEVECO_HOME` 指向 IDE）；可使用 `--live` 加 `TALEBOOK_URL`、`TALEBOOK_CODE`、`TALEBOOK_KEYWORD` 验证授权 NAS，凭据仅从环境读取，不写文件。该主机测试不替代设备上的播放、恢复、下载及导出验证。

## 阅读与播放

- 阅听记录每本书提供“历史记录”，独立 `reading_sessions_v1` 保存阅读、音频和 TTS 的章节会话起止时间、章节身份、起止毫秒/字符位置；支持跳回开始或停留位置。记录最多 2000 条，异常退出显示最后保存时间；不从旧版最新进度推造历史。
- 系统 TTS 使用 `playType: 0` 获取 PCM，按序号去重重排、校验格式并限制单句 8 MiB，再封装 WAV 复用 App 内 AVPlayer 播放；真实播放完成才推进正文，停止会取消迟到音频并清理临时文件。后台模式不变时不重复 update，系统取消/挂起后不定时强制重申。锁屏 11 分钟问题仍需真机长时验证。
- 预缓存设置保存成功后立即重新调度当前书，失败回滚且提示；搜索并发保存后下次搜索生效，启动恢复均读取 Preferences。两项设置的“应用”均有成功/失败反馈。

- 阅读的“系统字体”不指定固定字体族；正文、预览与分页使用当前系统字体，导入字体继续显式注册。系统字体、字号或字重配置变化时按原章节与字符位置重新排版，普通前台恢复不重复重排。
- 在线小说用 `OnlineTextPaginator` 分页，按章节标题或索引及 `charOffset` 恢复位置；切换字号和窗口尺寸后重新分页。阅读入口先恢复本地目录，缺失才联网并保存目录。章节正文有内存缓存、请求合并和相邻章节预取；已读和预读正文经 `OnlineTextContentCache` 写入 `files/online_text_content`，按书源、书籍及章节地址隔离，重启后先读本地，缺失或损坏才联网。系统普通清缓存不会删除已保存正文，应用内按书清理仍生效，不代表已下载全书；单章缓存上限 8 MiB，写入失败不阻断阅读。
- 正文默认两端对齐，字体面板可改为左对齐、居中或右对齐；偏好持久化并参与阅读备份。分页和连续滚动保留同一原生 Paragraph 的完整排版，以 FrameNode 仅绘制可见原生 TextLine（保留整章坐标并减去当前块顶部偏移），避免独立单行 Text 的段末规则使两端对齐失效；朗读高亮使用该排版的字符矩形，API 20 的 updateColor 切换文字颜色，不重新测量。
- 分页前为每个非空正文段落统一添加两个全角空格，测量与显示共用排版文本；页起止偏移映射回清洗后的原文，新增缩进不改变阅读进度的字符坐标。跨页续行不补缩进，正文段落不做启发式合并。
- `ReaderPage` 还保留已有 EPUB 路径的 ReaderKit 分支及 `EpubReaderComponent`；ReaderKit 组件和 BookParser 均通过动态 import 隔离（import lazy 不能阻止 HSP 链接）；控制器仅在旧 EPUB 分支通过 ReaderCore/BookParser 能力检查后创建。缺少能力时旧 EPUB 阅读和 EPUB 导入显示不可用提示，不影响启动及普通文字阅读。`ImportPage` 已支持音频、TXT/EPUB/MOBI/HTML/HTM 与 ZIP 批量导入；新导入电子书转为文字章节使用现有阅读器，尚无书签管理入口。
- 阅读页眉、页脚和电量时间与正文使用相同主题字色；四角可在章节名、页码/进度、章节序号、书名之间交换位置。每种内容保留显示开关，位置保存在阅读偏好并进入本地/云备份；旧配置默认保持原四角排列。
- 阅读页默认常驻显示系统状态栏，默认隐藏“章节 / 设置 / 字体”悬浮栏；阅读设置关闭“始终显示状态栏”后，状态栏跟随悬浮栏显隐。自定义背景与翻页纸面按完整视口绘制并延伸到状态栏和底部系统区域，正文和操作按钮动态避让横屏左右摄像头与系统区域，左右安全距离参与分页；顶部正文间距在用户边距基础上扣除默认的 12vp（最小 0），页眉高 22vp，不叠加顶部纯色遮罩。工具栏仅由轻点指定区域呼出，移动达到 8vp、多指、取消及拖动/滚动开始后均拒绝本次点击。API 22 起读取不受显隐影响的系统避让区，API 20–21 保留本次阅读已测得的高度；工具栏与弹层覆盖正文，显隐不改变分页视口。阅读路由仍在栈顶时，前后台切换保留阅读模式、安全区和当前页；最小化空避让区、零尺寸及未变化的主题通知不触发重排。离开阅读路由恢复系统栏，返回时恢复阅读模式，状态栏文字颜色跟随阅读背景。字体主题面板在标题下方常驻阅读预览，滚动区首项为主题；字号、行高、字重卡片压缩留白，正文对齐紧接字重之后。主题包含预设主题（羊皮纸／夜晚／纯黑／图片背景）与独立的自定义主题（5 套独立配色）。预设不受自定义颜色覆盖；图片独立记住蒙层与字色，5 套自定义主题分别编辑文字/背景颜色，草稿实时预览，保存并应用才提交，取消/关闭不改变设置。旧全局字色与图片配色兼容迁移；跟随系统只覆盖显示，手动选主题或保存配色退出自动模式。支持 14–50 字号、1.0–2.4 行高、100–900 连续字重及 TTF/OTF 字体导入（私有目录，32 MiB 上限）；正文与分页测量共用字体集合。阅读设置提供翻页、九宫格点击区域（上一页／工具栏／下一页／无操作，左右列宽与上下行高按百分比可调，至少一个工具栏入口，持久化并参与备份）、边距、亮屏时间（系统／1／5／10 分钟／常亮）、状态栏及页脚配置，滚动正文上下边界使用渐变模糊。图片支持更换及调整蒙层，自定义背景选项下方提供更换按钮；在线与本地章节阅读支持自适应、平铺、拉伸、裁剪四种背景显示模式，默认裁剪，选择独立持久化且不触发重新分页，旧 ReaderKit EPUB 通道保留原显示方式；翻页效果标题与选项同行，旧纯白、纹理与自定义色设置按兼容规则迁移。页脚默认显示电量与时间，开关独立持久化，不触发重新分页；阅读设置、章节、朗读及听书页弹层固定弱档（厚材质），不跟随全局材质偏好，旧系统固定使用厚磨砂回退。
- 详情页点击总集数在原目录区域切换列表与双列分段卡片，不打开新页面或弹层；分段每 40 章，切换后保留全书搜索、章节排序和点章阅读/播放。听书与阅读章节弹层默认使用列表，点击总集数切换双列分段目录，同时定位当前章所在分段和具体章节，保留搜索及点章播放/阅读，听书保留长按下载。设置预缓存支持 0–50 章，0 关闭，选择项、输入框和应用按钮同行，存取及备份恢复均校验范围。
- 音频预缓存由单个后台队列完成解析与整章下载，入队去重；当前章开始播放且未缓冲时，优先解析并下载播放方向上的紧邻下一章，再保存当前章供回听，随后从近到远预取其余章节。前台解析出的音频 URL 和请求头也写入共享缓存，快速回听无需重复解析。切章只命中已完成文件，未完成立即取消重复传输并交给 AVPlayer 拉流，不等待整章下载；目标章正在解析时保留嗅探并复用同一解析及请求头，失败回退前台解析。后台目录准备与音频解析共用书源配置的超时预算（默认 15 秒），超时放行后续队列，迟到结果不再写入缓存。缓冲时暂停预取，恢复后补齐；暂停播放后继续完成已安排的有限预缓存队列；关闭预缓存同时取消下载并使旧解析失效。解析 URL 最多复用 5 分钟，下载失败移除 URL 后按 30 秒冷却重试。预加载音频存放于 filesDir，1GB 音频淘汰只扫描完整 mp3，排除播放中和正在发布的文件；磁盘清理串行合并。文字阅读仍独立预取前后各一章。
- AVSession 冷启动提前初始化并激活，书名和章节先发布、封面异步补齐，旧封面回调不能覆盖新书。播放器定时未启用时显示时钟图标，启用后隐藏图标，仅显示剩余时间／章数；弹层关闭期间阻止同次点击重开。
- AVPlayer 负责播放、音频焦点和续播，`AVSessionService` 对接系统倍速、上下集和收藏，后台任务维持收听。
- 耳机摘戴通过 AVPlayer 的 `audioOutputDeviceChangeWithInfo` 与 AVSession 播控适配：旧输出设备不可用时暂停并取消焦点自动恢复，加载完成也保持暂停；支持佩戴检测的耳机/系统下发 `play` 后按原进度续播。重复 `play`/`pause` 保持各自语义，设备重新连接本身不触发播放。
- 设置的“启动”分组提供“打开软件自动播放”，默认关闭并随通用设置备份。开启后，冷启动完成播放状态恢复且进入前台时尝试续播上次章节和进度；没有可恢复内容时不播放，普通后台返回不重复起播，跨设备续播及卡片控制优先。
- 播放页封面左上角显示来源；上排提供后退15秒、上一章、播放/暂停、下一章、快进15秒，下排为倍速、闹钟（右上角定时角标）、跳过头尾、章节。横屏采用左侧正方形封面、右侧章节信息与全部播放控件的布局，右栏高度不足时独立滚动，旋转不改变播放状态。进入页面使用顺序播放并移除模式切换，末章自然结束或跳过片尾后停止。支持 0.5x–3.0x 倍速（减/加每次 0.05x）、片头片尾跳过（减/加每次 1 秒）、睡眠定时和 HTTP(S) URL 投播，倍速及跳过面板为 55% 高。定时支持按时长（15/30/45/60 分钟、自定义 1–1440 分钟）或按章节（本章、3/5/7 章、自定义最多 999 章且不超过目录剩余数），预设点选、自定义键盘完成后立即生效。章数包含当前章，按目录顺序播放，停止先于续播/循环，片尾跳过计为章末；手动暂停保留、手动切章切书取消章节停止。智能停止仅在到时仍在播放且本章剩余时长大于 0、不超过 10 分钟时等待章节结束，可取消等待，切换开关不重置倒计时。
- 在线 `MediaSource` 系统缓存与用户主动章节下载分开；下载文件可经系统文件选择器导出副本。HLS（含直播探测失败的 m3u8）及已识别直播不启用 `enableOfflineCache`，避免滚动清单进入固定资源缓存路径后耗尽、反复缓冲重连；M4A/M4B/MP4/MOV 同样使用普通网络播放，保留尾部索引的 Range 寻址，避免系统离线缓存拖慢首播，其余普通音频仍按 API 23 门槛启用系统缓存。电台回归需持续播放超过两个清单窗口，并检查分片、音频输出位置持续推进，不能仅以起播成功判定通过。
- 迷你播放器封面和完整播放页封面保持静止，迷你播放器外圈展示当前集进度。

书架在线更新沿用 FavoritePage → BookSourceService → 已导入源的详情与目录链路。ShelfUpdateService 使用本机 `listenbook_shelf_updates` Preferences 保存每日尝试日期与最近更新报告，不纳入备份；首次进入书架或书架回到前台时按本地自然日静默检查一次，手动刷新可重试，同进程所有入口互斥、最多三本并发。自动检查不弹窗，用户可从书架工具栏查看沉浸光感更新列表。

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

书架在线书索引存 `files/library_books_v1.json`，章节目录存 `files/library_toc`，正文存 `files/online_text_content`，预加载音频存 `files/chap_*.mp3`。升级启动将旧 cacheDir 资源复制到持久目录，校验大小并发布后才删除原文件；书架优先迁移当前 cacheDir 数据，再兼容更早 filesDir 数据，防止旧残留覆盖新数据。系统普通清缓存后可继续使用已保存资源；应用内清理、音频 1GB 淘汰、清除应用数据或卸载仍按各自规则删除。临时解压、临时语音与可再下载图片仍使用 cacheDir。

`StatsService` 将已恢复的收听统计保留在服务缓存中，计时、删除、清空和恢复操作串行写入 `listenbook_stats` Preferences 与 `files/listening_stats_v3.json` 独立快照。文件通过临时文件、fsync 和重命名替换，启动时按修订号选取有效数据；两份数据均读取失败时不允许按空记录覆盖。旧统计自动迁移，累计时长独立于每日明细保留窗口，跨天与重启不归零。记录页的顶部摘要先于书籍明细更新，明细失败不阻断累计展示。

`MedalService` 使用 `listenbook_medals` Preferences 保存已解锁勋章及单枚佩戴 ID（空 ID 表示主动取消佩戴），通过 `StatsService` 统计事件自动解锁 1/10/50/100/300/500/1000/2000/5000 小时勋章。启动补发历史时长、备份恢复均不虚构获得日期；删除统计不收回已获得勋章，新解锁不替换佩戴项。服务使用 ArkUI V2 可观察单例同步独立“成就馆”页与“我的”，应用启动初始化、后台/退出等待落盘；本地与云备份共用的 `AppBackupSnapshot.medals` 是可选字段，旧备份兼容，恢复合并已获得集合并恢复佩戴选择。成就跟随本地数据，不按登录账号分割，登录仅控制展示。勋章序列化字段须保留混淆名称。

收听统计使用包含系统休眠的单调时钟结算实际播放时长；音频暂停、缓冲、切章和释放时结算尾段，缓冲不计时，倍速、拖动和系统校时不改变已听时长。音频与朗读上报结束时刻，统计服务按自然日拆分跨零点区间。顶部累计、本月和连续天数取统一服务快照，本月只累加当月截至今天的每日明细；缺少日期的旧累计仅保留在总计，不按书籍更新时间猜测月份。页面可见及跨日时刷新，统计事件直接刷新摘要，不等待书籍明细。删除书籍或记录将统计标记 archived，列表隐藏但累计与每日统计保留，再次收听恢复明细。旧备份恢复按书与日期取较大值合并，不降低本机累计；仅设置页专门确认的 resetListeningTime 清零统计。独立快照的 version/revision/records/archived 字段保留混淆名称。

规则数据库使用 S2 安全级别和加密。备份迁移在线收藏、阅听记录、阅读与播放进度、常规阅读设置、逐书目录顺序、朗读进度与设置、统计、通用设置、书籍元数据及清洗后的书源定义；不迁移实际登录会话、Cookie、敏感 Header Token、原始书源 JSON、下载音频及本地导入文件。来源恢复后回到“待测试”。`ReadingBackupService` 将独立阅读和朗读 Preferences 的白名单字段加入快照；自定义背景、配色、字体文件及路径不迁移。旧快照没有 reading 字段时保留本机阅读数据。

跨设备迁移携带在线书当前章节、原始章节地址、进度、时长、倍速和播放状态，目标设备再补齐目录；不是全量文件或书源账号同步。

### 电子书离线朗读

在线小说阅读页通过右侧独立“听”字沉浸悬浮圆按钮（随底栏同步显隐）打开朗读面板，提供系统 CoreSpeechKit 离线 TTS，`TextToSpeechService` 独立于页面生命周期，支持按句播放、0.5–2 倍语速、查询/下载/切换音色、跨章预取、自然段整体高亮与正文翻页跟随、定时停止及读完本章停止。退出阅读页后可通过首页迷你朗读栏、锁屏和耳机继续控制；焦点丢失或耳机断开时暂停，不自动恢复外放。EPUB 的 ReaderKit 分支暂不接入朗读。 “听”面板的朗读引擎使用与自定义字体一致的沉浸下拉标签，支持 JSON 文件批量导入、粘贴、切换和删除 HTTP TTS，保存音色库和选中项，删除当前音色回退系统语音。轻页配置兼容 `@URL` POST 表单、`url,{options}`、对象或字符串 JSON 请求体，以及 `java.encodeURI(speakText)`／语速模板（`speakSpeed=round(speed*10)`）；模板只调用有界 QuickJS 门面，不提供平台或网络桥。接口直接返回音频，同一自然段的短句优先合并为约 64 字的朗读片段，纯标点不单独合成；连续片段复用同一个 AVPlayer，切片段只 reset，暂停/停止/失败时释放。播放当前片段时串行预取后两个片段，窗口最多三个，每片段音频最多 8 MiB，缓冲命中时不切入加载状态；模板未使用语速变量时才由本地播放器调速，切换或暂停会取消旧请求并释放临时音频。

朗读复用导入源正文与 `OnlineTextContentCache`，没有新增服务端或内置内容源。`text_to_speech` Preferences 独立保存设置与按书的来源、章节 URL、字符位置；目录重排按 URL 恢复，暂停从当前句起读。阅读翻页不覆盖朗读进度。朗读尚不生成可下载/导出的音频文件，不提供时间轴拖动或远程投播。

`PlaybackCoordinator` 保证朗读与原有音频互斥，`AVSessionService` 根据当前播放类型切换系统回调并屏蔽旧播放器更新；后台音频任务分别记录 audio/speech 持有者。仅实际播报阶段计入 `StatsService` 收听统计。系统 TTS 仅合成音频，App 内 AVPlayer 播放，应用音频会话的空闲超时不视为抢占；真正的焦点抢占仍暂停。朗读开始后整体高亮所在自然段，同段多句保持同一选中范围；不估算逐字位置，不运行高亮刷新定时器。切段更新高亮，跨页按实际朗读句起点跟随，回前台同步当前位置。独立朗读 Preferences 的在线进度及语速、音色、语言和跟随设置通过 `ReadingBackupService` 加入备份。

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

1. 修改 `.ets` 前在线读取适用的 ArkTS 语法与 ArkUI 技能，遵循 [AGENTS.md](AGENTS.md) 的最低 API 20、目标 API 26 / ArkUI V2 约束。
2. 对修改文件运行 `arkts_check` 或现有工具对应的 `check_ets_files`，再运行 `build_project` 增量构建；成功后用 `start_app` 真机或模拟器验证。发生 ArkTS 错误先在线读取对应的编译修复技能。
3. 工具不可用时使用 `ohpm install`、`hvigorw assembleHap --mode module -p product=default`；`release` 产品用于发布配置。只在确认缓存问题时清理构建。
4. App 单测位于 `entry/src/test/`，涵盖本地规则、原生适配、批量测试、搜索缓存与历史、在线分页、阅读主题、播放进度和下载策略；设备测试位于 `entry/src/ohosTest/ets/test/`。
   - 播控事件回归：`DEVECO_HOME` 指向已安装 IDE 后运行 `node scripts/test-audio-commands.cjs`，以模拟平台事件执行真实 `AudioService`，覆盖耳机摘下、AVSession 重复指令、加载中暂停和迟到焦点恢复；实际佩戴检测仍需耳机真机验证。
   - 书源回归设备类：`LocalRuleCompatibility,LocalRuleFeatures,LocalRuleRuntime,LocalRulePersistence,LocalRuleRequestLimiter`。HTTP/网页集成另启动 `node scripts/local-rule-http-fixture.cjs`，用 HDC 映射 `rport tcp:18997 tcp:18997`，运行 `LocalRuleBrowserIntegration` 并传入 `-s fixtureUrl http://127.0.0.1:18997`；结束后停止服务并移除该映射。
   - `LocalRuleImportedSmoke` 仅在显式传入 `sourceUrl` 时访问实际来源，可用 `importUrl` 临时导入缺失定义，完成后清理临时来源。`SourcePlaybackSmoke` 的 `playbackImportUrl`、`playbackSourceUrl`、`playbackKeyword` 参数覆盖搜索到实际起播和暂停续播，设备测试静音播放。
5. 服务端校验使用 `npm run typecheck`、`npm test`、`npm run build:all`；部署细节见 `server/README.md`。

来源与阅读改动应验证“无导入源空态 → 导入 → 单源/批量测试 → 搜索 → 详情 → 阅读或播放”，以及禁用后的收藏解析、单源失败隔离。播放与下载改动应验证切章、续播、系统控制、下载和导出。UI 改动按 `docs/APP_UI.md` 回归。

华为账号登录入口位于“我的”顶部，与书源管理行尺寸一致。`AuthService` 使用 `createAuthorizationWithHuaweiIDRequest` 和 `profile` scope，严格校验 state 和身份字段，获取昵称与头像；不请求服务端授权码或保存 Client Secret。`AccountAvatarService` 仅通过 HTTPS 下载最大 2MiB 的头像，限时请求并在本机缓存，不保存临时头像 URL。旧登录缓存保留兼容，更新资料由用户主动授权。通过 `getHuaweiIDState` 核对本机缓存与系统账号；系统退出或换号后清除原资料，临时服务异常保留缓存供重试但不展示已登录。退出清除本机资料并保留业务数据与云备份。

“我的”顶部账号行统一进入 `AccountPage`，提供登录、资料更新、退出及个人华为云空间备份/恢复。`AppScope/app.json5` 开启 `cloudFileSyncEnabled`，`CloudBackupService` 使用 `Context.cloudFileDir`、`cloudSync.FileSync`（API12）、`CloudFileCache`（API11）和 `getCoreFileSyncState`（API20）；均不超出最低 API20。云文件按 OpenID 的 SHA-256 摘要区分，不将账号资料放入快照。上传在完成事件及文件成功状态均确认后才算成功；同步/下载有两分钟超时、取消和监听清理，并检查系统账号。云空间使用的是用户账号配额，没有新增服务器或用户数据表。

云文件与本机暂存文件之间使用有大小上限的分块读写，处理短读、短写，避免快捷复制依赖的文件系统扩展操作。云目录覆盖重命名在实机上返回 `13900020`，因此每次使用账号摘要、递增版本号和 UUID 创建新文件，完整写入 `.pending` 后只重命名到尚不存在的目标。同步回调可能早于实际文件上传完成，需等待启动请求成功并轮询本次文件状态；两分钟内未确认上传则提示超时。确认新文件上传后保留最新两份已同步备份，清理失败不影响新备份。恢复选择当前账号最新已同步版本，兼容原固定文件名，忽略临时文件及未完成上传。复制失败或取消时保留原备份，并在账号仍一致时清理临时云文件。错误区分本机快照准备、云文件读写和系统同步；FileIO 空间不足使用 `13900025`，云服务内部错误 `22400005` 归入同步异常。页面保留系统错误码供用户反馈，日志只记录操作、阶段、分类和错误码，不记录账号、文件路径或备份内容。

`AppBackupService` 复用系统快照白名单，手动本地/云模式不吞掉书源读取/写入错误。快照包含搜索、发现（含分页）、详情、目录、正文规则及书源管理状态；新增字段在旧版 v2 快照中可缺省。导出时在独立副本中兼容已发布版本混淆过的历史时间戳、章节索引和播放位置，保留可恢复的记录及数值；无法恢复或不符合格式的历史、逐书播放进度、阅读/朗读进度和统计逐条跳过，不改写本机记录。校验允许未知时长 -1 和合法负数书源排序；导入文件仍严格校验，存储或书源读写失败仍报错。恢复同地址书源遵循仓库的管理状态保留及锁定保护。恢复前限制 32MiB 并校验完整快照，向用户展示备份时间和数量，确认后才写入；保留本地导入数据及锁定源。云恢复写入前保存 `filesDir/backup/before_cloud_restore.json`，此文件不在系统备份白名单或云目录；跨多个本地存储的恢复不是事务，失败时会提示未全部完成并保留快照。不会上传下载音频、导入文件、自定义阅读背景/配色/字体或书源登录会话。系统云服务未就绪、账号/应用同步未启用等需要设备端配置，代码编译与模拟测试不代表服务已开通。

本地备份仅保留在 `AccountPage`，未登录也可通过“我的”顶部账号行进入。`LocalBackupService` 使用 `DocumentViewPicker(context)` 的保存/选择接口及 `fileIo` 描述符读写，所有使用的 API 均兼容最低 API20。文件 URI 只在当前操作中使用，分块复制处理短读/短写及文件增长，保存完成后才报成功。本地备份为完整快照 JSON，不把独立书源数组当作恢复文件。恢复前保存并验证 `filesDir/backup/before_local_restore.json`；取消选择/确认不恢复业务数据，失败保留安全快照。本地操作通过 `AuthService.beginDataOperation(false)` 与云备份、资料授权、退出互斥。回归使用 `DEVECO_HOME=<Release IDE> node scripts/test-local-backup.cjs`，共享真实服务转译与文件模拟设施，并覆盖书源字段往返、无登录、取消、损坏/超限文件、失败和资源释放。

`AutoBackupService` 在账号页华为云空间卡片提供默认关闭的自动备份，支持 1/3/7 天间隔。服务初始化完成后在前台延迟 10 秒检查，前台每分钟检查到期条件，退后台清理定时器并取消本次自动传输；下次前台按退避时间补做。复用云备份互斥、完整快照校验及上传确认，内容 SHA-256 排除导出时间，无变化不生成新云版本；失败从 5 分钟指数退避至最多 6 小时。独立 `auto_backup_local` Preferences 以账号摘要为键保存开关、频率、成功时间、摘要和重试状态，不进入系统/本地/云备份白名单，JSON 字段保留混淆名称。新安装或该账号从未在本机备份/恢复时，先同步检查云目录，发现已有备份暂停自动上传；用户恢复成功或明确确认使用本机数据手动备份后解除保护。手动备份成功更新调度，云恢复不冒充上传成功；调度写入失败停止自动尝试并单独提示。手动操作先取消并等待自动任务释放，账号页退出不取消自动任务，系统换号后不沿用另一账号授权。隐私政策 v3.4.0 同步说明主动开启和前台执行边界。回归：`node scripts/test-auto-backup.cjs`，使用 Release IDE 的 Node 和 `DEVECO_HOME`。

个人云空间配置：官方端云文件协同指南要求设备系统至少 HarmonyOS 6.0.0.115、云空间至少 6.0.0.300，使用 API21 以上正式版 SDK 构建（本工程已满足）。安装带有 `cloudFileSyncEnabled` 的应用后，在系统“设置 → 云空间”找到“简听阅读”并打开同步开关；跨设备恢复须使用同一华为账号。本路径无需接入开发者 AGC 存储桶。低于服务要求或没有开启应用同步时，页面提示云空间不可用，原有本地功能仍可使用。

`entry/src/main/module.json5` 配置的是 AGC 应用级 OAuth 2.0 Client ID `6917615941058168740`，不能使用项目级 Client ID。调试和发布时还需在 AGC“应用 → SHA256证书/公钥指纹”登记实际签名公钥的 SHA-256；更换签名后重新核对。客户端不保存 Client Secret。配置依据：[华为账号登录 API](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/account-unionid-login-api)、[配置 Client ID](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/account-client-id)、[账号状态 API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/account-api-authentication)。本机模拟回归使用 `DEVECO_HOME=<Release IDE> node scripts/test-huawei-auth.cjs`，真实登录仍以设备授权和 AGC 配置验证为准。

本轮资料依据：[头像昵称在线技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-development/hmos-one-sdk-skill/hmos-sdk-basic-skill/Account%20Kit(华为账号服务)/hmos-account-kit-get-avatar-nickname/SUB_SKILL.md)、[头像昵称授权指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/account-get-avatar-nickname)、[应用文件云同步](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/app-cloud-sync-filesync)、[ArkTS 语法指南](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/07-tools/tools/deveco-studio/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkUI 检索指南](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-development/01-application-framework/ArkUI/hmos-arkui-knowledge-retriever/SKILL.md)。API 及版本以安装的 Release SDK 声明复核。云状态和恢复校验模拟回归：`DEVECO_HOME=<Release IDE> node scripts/test-cloud-backup.cjs`；使用 Release IDE 内置 Node，避免 PATH 中旧 Node 不支持 `node:` 模块。

产品或交互变化直接更新现行文档；已失效的一次性计划和修复说明删除，历史由 Git 保留。

音频手动暂停、卡片暂停和定时结束后，已启用的当前章及配置窗口预缓存继续收尾，不再因 paused 事件清空队列；队列通过独立 preload owner 持有 dataTransfer，与手动下载互不释放，队列耗尽（含失败）后释放。播放缓冲、显式关闭预缓存、清理及退出仍按原规则取消；预缓存设为 0 的关闭语义保留，HLS/直播仍不保存为完整音频文件。

### 本地导入容量与格式

系统文件管理器“使用简听阅读打开”：JSON 自动进入书源导入；TXT/EPUB/MOBI/HTML/HTM 和 ZIP 自动进入本地导入页并带入文件、预览书名/作者/封面，点击“开始导入”入架，无需再次选文件。优先按文件后缀分流，无后缀 URI 使用 MIME/UTD 类型；冷启动和应用已运行时均支持，保留原始授权 URI，文件打开不触发启动自动播放。压缩包仅声明当前支持的 ZIP。


- 音频支持 MP3/M4A/FLAC/WAV/OGG/AAC，电子书支持 TXT/EPUB/MOBI/HTML/HTM；ZIP 中音频自然排序成书，电子书逐本入架。每次文件选择上限 500，可继续追加。
- 单 ZIP 处理上限 32 GiB、解压内容 64 GiB，包内最多 100000 个文件/目录、50000 个可导入文件；单书最多 50000 章/集。导入前校验剩余空间并保留 256 MiB，多 ZIP 顺序解压并逐包清理。容量为代码上限，不代表已做同等体积设备压力验证。
- TXT 最大 256 MiB，64 KiB 流式解码 UTF-8/UTF-16/GB18030，识别章节标题并限制正文片段长度；HTML/HTM 最大 32 MiB，EPUB 最大 512 MiB、解压内容最多 2 GiB，使用系统 BookParser 按 spine 提取文字。EPUB 优先读取原始 HTML，失败才调用排版接口；TXT/HTML/MOBI/EPUB 共用最多 4 路异步章节写入，进度按 150ms 节流。音频最多 4 路复制/时长探测，ZIP 临时音频直接移动；失败先等待在途任务再回滚目录。日志记录各阶段耗时及 EPUB 原文/排版命中数量。
- MOBI 最大 128 MiB、解压正文最大 32 MiB；支持未加密 MOBI6 的未压缩/PalmDOC 记录和混合文件的 MOBI6 部分，UTF-8/Windows-1252 解码，提取书名/作者，按标题或分页标记分章，长章继续限制为 32000 字符；自动提取内嵌封面（原封面优先、缩略图回退），不保留正文图片和原排版。加密、HUFF/CDIC、纯 KF8/AZW3 或损坏文件明确报错并清理半成品。
- 新导入目录存 filesDir/imported_toc，偏好索引只存书籍元数据；正文存 filesDir/ebooks。读取本地正文限定本书路径，不依赖网络书源；删书同时清理目录和正文。ZIP 音频直接移动入库，大于 500 集时不逐集探测时长，播放后补齐。

播放页右上角按“刷新图标 / 上下排列的左右箭头换源图标 / 详情图标”排序，详情位于最右侧，三个按钮使用透明背景纯图标，不应用沉浸光感材质；在线电子书阅读页显示工具栏时，右上角显示刷新、换源、详情图标入口，整体左移并按页码实际宽度预留空间；详情从底部 Tab 移至右上角，本地电子书也保留详情入口。底部仅保留章节、设置、字体；章节弹框使用系统最大高度，打开时保持状态栏可见并避让。正文加载失败时仍可操作顶部入口。重载重新获取当前章音频/正文并保留时间或字符位置，音频绕过预缓存和已下载文件（不删除用户下载），文字绕过内存与磁盘缓存。换源在发起请求前按当前书籍类型筛选已启用的其他导入书源：电子书仅搜索 bookSourceType=0/3，有声书仅搜索 bookSourceType=1；漫画及未知类型不参与，进度总数只统计匹配书源，返回结果仍校验内容类型。六个搜索位置空闲即接续，单源等待最多 30 秒；自动去除书名版本后缀，按关键词包含关系与内容类型筛选，支持修改书名、停止搜索，展示搜索进度并保留成功结果。搜索 loading 位于停止搜索按钮内，停止立即结束本轮等待并冻结结果和进度，迟到回调不再更新面板；面板标题左上对齐，文字跟随系统深浅主题；选择来源后按钮显示“正在加载章节…”，停止来源搜索并加载目录；优先按唯一同名章定位，否则按当前章节序号定位（超出新目录时定位末章），目录自动滚动并高亮该章，允许继续或手动选章。同名章可保留章内进度，按序号定位的不同版本从章首开始。先验证目标章节能解析音频地址/取得正文，再保存新书身份和替换路由；旧收藏与旧来源进度保留，不混用两来源缓存。本地导入文件不提供在线换源。

## 标准手表独立听书

`EntryAbility` 根据系统设备类型分流至 `WearableRuntime` / `WearablePage`，保留同一模块和用户导入内容架构。手表支持 HTTPS 书源导入（响应上限 2 MiB）、有声书搜索、收藏、目录、逐集播放、15 秒快进/快退、上一集/下一集、当前集或当前起 5 集下载、队列暂停/重试及本书下载删除。离线目录从原持久缓存读取；规则解析和音频提取按需挂载原有受限 ArkWeb 宿主。关闭自动章节预加载以控制手表资源消耗，主动下载复用原队列。

账号通过 `AuthService.restoreSharedAccount` 先校验缓存，再尝试不强制弹窗的系统授权；只有响应 state 校验通过的真实系统身份可落盘。手机登录并不保证任意手表自动获得授权。系统授权可恢复时免重复登录，其他情况提供重试和显式授权。可从同一华为账号的既有手机云备份恢复书架、书源和进度，确认后执行已有备份恢复流程；不自动覆盖数据、不复制手机音频、不新增云服务器或 Wear Engine 身份信任协议。

仅覆盖 API 20+ 的标准 `wearable`，不是所有 WATCH/GT 型号的兼容承诺。`liteWearable` 缺少当前 ArkUI V2/AVPlayer/关系数据库运行链，尚无该平台实现。设备型号、固件 API、ABI、应用安装权限及真实播放/账号恢复必须在手表验证。主机定向回归：`DEVECO_HOME=<Release IDE> node scripts/test-wearable.cjs`。

- 搜索并发默认 3，会员可自定义 1–12；非会员点击修改跳转订阅。读取旧配置及恢复备份都强制回到 3，重新开通不会复活旧自定义值。
