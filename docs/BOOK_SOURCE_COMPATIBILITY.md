# 简听与 Legado 系书源的兼容性

核对日期：2026-09-22。本文用于维护通用书源兼容边界和补齐顺序，与 [书源编写指南](BOOK_SOURCE_RULES.md) 配套。

## 比较基线与结论

- 简听：`D:\HSDA` 当前工作区，包含本次会话已完成的模板表达式、URL 派生 `id`、详情 `book.bookUrl` 补充。
- 对照仓库：[Luoyacheng/legado-E](https://github.com/Luoyacheng/legado-E)，本地 `D:\legado-E`，默认分支 `main`，提交 `8b87c5aba4df91c39a3a0939a68a1180b9f2ee1c`（2026-08-01，提交说明“优化工作流文件”）。本地为浅克隆，当前提交的工作树完整，未下载完整历史。
- 该仓库 [README](https://github.com/Luoyacheng/legado-E/blob/8b87c5aba4df91c39a3a0939a68a1180b9f2ee1c/README.md) 自称“阅读 Sigma”，继承 `gedoor/legado`，并增加歌词、视频、弹幕、事件等功能。本文对照的是这个指定分支，不能把全部功能直接归为原版阅读 3.0；未对原版历史逐项做版本溯源。

简听已有搜索、发现、详情、目录、正文/音频的通用执行链，具备 CSS、XPath、JSONPath、正则、QuickJS、受控网络、登录与动态网页能力。差距集中在 **阅读规则的准确语义、宿主接口契约和阶段钩子的覆盖**，而非缺少 JavaScript 引擎。普通规则具备迁移基础，但复杂现成书源不能据此认定可原样导入运行。

以下结论以模型、解析器和实际调用处为依据；少量确定性的脚本差异用简听现有 Node 回归装载器做了模拟验证。未编译/运行 Android App，未做两端同源真机成功率、性能或站点可用性测试，因此不给兼容率百分比。

## 页面、服务与数据链

| 阶段 | Legado-E | 简听 |
| --- | --- | --- |
| 导入/编辑 | `BookSourceEditViewModel`、Gson、旧源转换；Room `book_sources` 和 `BookSource`/各 `rule` 模型 | `LocalRuleSourceImportParser` → `LocalRuleSourceRepository`；加密 `rule_sources.db`，未知字段保留于原始定义 |
| 搜索/发现 | `WebBook` → `BookList` → `AnalyzeUrl`/`AnalyzeRule` | 页面 → `BookSourceService` → `LocalRuleDispatcher` → URL/HTTP/阶段提取器 |
| 详情/目录 | `BookInfo`、`BookChapterList`；真实 `Book`/`BookChapter` 对象参与脚本与持久变量 | `LocalRuleDispatcher` 返回详情和目录数据；字符串变量随书籍、章节传递 |
| 正文/音频 | `WebBook` → `BookContent`，再进入文本、音频、漫画或视频消费链 | `LocalRuleDispatcher.resolveContent` → 文本分页或音频播放/下载 |
| JS | Rhino，JSoup/JXNode/Java 对象及宿主接口 | `LocalRuleScriptRuntime` → 独立受限 QuickJS；外部动作经过受控桥与响应重放 |

简听的光遇、书山、听友等导入源协议适配是独立能力，不能计为通用 Legado 规则兼容；可选 `server/` 也不参与 App 本地兼容结论。

## 已确认的关键差异

### 1. 同名 JavaScript 接口存在不一致——优先修复

| 接口/示例 | Legado-E 当前实现 | 简听当前实现及影响 |
| --- | --- | --- |
| `java.base64Decode('aGVsbG8=')` | 返回文本 `hello`；字节数组另用 `base64DecodeToByteArray` | 后加载的兼容层把 `base64Decode` 覆盖成字节数组解码，返回 `[104,101,108,108,111]`；解码后直接 `JSON.parse` 的规则会失败 |
| `java.timeFormatUTC(0, 'HH', 28800000)` | 参数传给 `SimpleTimeZone`，单位是毫秒；此例为 `08` | 兼容层按小时偏移处理；模拟执行此例得到 `00`。签名或时间参数可能出错 |
| `java.hexDecodeToByteArray` | 已有独立方法 | 当前未提供此名称；已有 `hexDecode` 并不等于原样脚本可调用 |
| `java.ajaxAll` | 按配置并发请求，返回 `StrResponse[]` | 已有方法，但通过动作重放逐个补齐响应；不能称为“缺失”，也不能视为同样的并发语义 |
| `java.ajaxTestAll`、`webViewGetSource`、`webViewGetOverrideUrl` | 有实现及多个重载 | 当前未提供同名接口；已有 `java.webView` 不能直接替代全部调用约定 |

依据：E 的 `help/JsExtensions.kt:128, 155, 241, 266, 581, 620, 640`；简听 [LocalRuleScriptCompat.ets](../entry/src/main/ets/service/rulesource/LocalRuleScriptCompat.ets)、[LocalRuleScriptRuntime.ets](../entry/src/main/ets/service/rulesource/LocalRuleScriptRuntime.ets)。尤其要检查最终覆盖后的方法，不能只看运行时前面同名方法已经存在。

### 2. 登录检查是不同的执行阶段

E 的 `WebBook.kt` 在搜索、发现、详情、目录、正文请求后调用 `loginCheckJs`，向脚本传入响应对象并采用返回的 `StrResponse`；部分异常路径也调用它。书源可以在此检查认证状态、刷新会话或重取响应。

简听当前在 `LocalRulePanelService.checkLogin` 和 `RuleSourceLoginPage` 的登录完成流程中检查，按返回文本 `false` 判失败；通用搜索/详情/目录/正文请求链没有同等的响应拦截钩子。

**影响：**即使两边都能保存 Cookie，依赖 `loginCheckJs` 在日常请求中续期或修正响应的书源仍可能不能使用。补齐时需设计响应对象与失败语义，并限制重试、递归和动作预算，不能只追加一次布尔检查。

依据：E `model/webBook/WebBook.kt:70, 141, 216, 313, 415`；简听 [LocalRulePanelService.ets](../entry/src/main/ets/service/rulesource/LocalRulePanelService.ets)、[LocalRuleHttpClient.ets](../entry/src/main/ets/service/rulesource/LocalRuleHttpClient.ets)。

### 3. 目录阶段缺少钩子，分页与分卷行为不同

| 能力 | E 的实际行为 | 简听当前行为 |
| --- | --- | --- |
| `ruleToc.preUpdateJs` | 更新目录前运行，可配合 `reGetBook()` / `refreshTocUrl()` | 规则模型未映射，也未执行；依赖动态目录地址更新的源会受影响 |
| `ruleToc.formatJs` | 汇总、排序、去重并确定索引后格式化标题；提供 `index`、`title`、`chapter`、`gInt` | 未映射、未执行；用单章 `chapterName` 规则不完全等价 |
| `nextTocUrl` 返回多个地址 | 区分一个地址的连续翻页与多个地址的并发获取 | URL 提取只采用第一个有效地址，其余分页会遗漏 |
| 列表前缀 `-` / `+` | 识别两者，并在跨页汇总过程中处理顺序 | 当前识别 `-`，逐页反转选中列表；未按同一语义实现 `+` 和跨页整体顺序 |
| 分卷条目没有 URL | 分卷可生成标题+索引标识；普通空 URL 也有回退 | URL 为空的条目先被跳过，尚未进入 `isVolume` 提取 |
| `isVip` / `isPay` / `isVolume` 真值 | 非空且不是 `false/no/not/0/0.0` 等值就视为真 | 只接受指定真值集合；例如规则返回 `VIP章节`，两边判断不同 |

依据：E `model/webBook/WebBook.kt:272`、`BookChapterList.kt:54, 74, 139, 240`、`utils/StringExtensions.kt:76`；简听 [LocalRuleDispatcher.ets](../entry/src/main/ets/service/rulesource/LocalRuleDispatcher.ets)、[LocalRuleStageExtractor.ets](../entry/src/main/ets/service/rulesource/LocalRuleStageExtractor.ets)。

### 4. 标准网页引擎不等于阅读选择器方言

- E 使用 JSoup 1.16.2、JsoupXpath 2.5.3 和 Jayway JSONPath；简听使用 ArkWeb DOM/CSS/XPath、自建 JSONPath 与旧选择链兼容层。
- 简听已处理常用 `class.` / `id.` / `tag.`、`:contains`、索引、`@text` / `@html` 等；JSoup 专有 `:matches`、`:containsOwn` 等不能直接交给浏览器 `querySelectorAll`，当前没有对应转换。
- JSoup 元素、JXNode 和 JSON 对象在 E 的规则链内保持原生类型。简听的 `java.getElement/getElements` 返回轻量元素包装，支持的方法集合与 JSoup `Element/Elements` 不同；例如不能假定完整的节点遍历和修改 API 都存在。
- E 的 Jayway 函数、过滤操作符与简听自建 JSONPath 不能仅按“都支持 JSONPath”判为等价。简听已有过滤、切片、递归下降；高阶函数及边界组合需要逐项用相同样例核对。
- E 的正则提取/替换依赖 Java Pattern，简听主要依赖 JavaScript RegExp；内联标志、Java 特有语法和替换语义仍有差距。

依据：E `model/analyzeRule/AnalyzeByJSoup.kt`、`AnalyzeByXPath.kt`、`AnalyzeByJSonPath.kt`、`AnalyzeRule.kt:482`、`gradle/libs.versions.toml`；简听 [LocalRuleWebRuntime.ets](../entry/src/main/ets/service/rulesource/LocalRuleWebRuntime.ets)、[LocalRuleJsonPath.ets](../entry/src/main/ets/service/rulesource/LocalRuleJsonPath.ets)、[LocalRuleJavaCompat.ets](../entry/src/main/ets/service/rulesource/LocalRuleJavaCompat.ets)。

### 5. 网页规则和请求选项覆盖不同

两边都有请求级 `webView` / `webJs`、响应转换 `bodyJs`、Header、Cookie、编码、重试和限流。简听并非只能解析静态 HTML。

明确缺口是：

- **`ruleContent.webJs`**：E 从正文规则组读取并传入网页请求；简听只识别 URL 选项中的 `webJs`，正文规则模型没有此字段。同名脚本位于不同层级会导致导入后不执行。
- E 的字段规则支持 **`@webjs:`** 分派；简听的规则脚本入口没有该分支。这属于指定分支的兼容范围，不能未经溯源归为所有原版阅读版本的要求。
- E 请求选项的 **`js`** 会在 URL 参数解析后再次变换地址；简听当前未消费该选项。
- E 处理 `webViewDelayTime`、`dnsIp` 等请求选项；简听采用自身受控网页等待策略，没有同等映射。
- E 请求模板有 **`<第一页值,后续页值>`** 分页选择形式；简听支持 `{{page}}` 及表达式，没有这套尖括号选择语义。

依据：E `model/webBook/WebBook.kt:417`、`model/analyzeRule/AnalyzeUrl.kt:190, 260`、`AnalyzeRule.kt:174, 556`、`constant/AppPattern.kt:9`；简听 [LocalRuleUrlAnalyzer.ets](../entry/src/main/ets/service/rulesource/LocalRuleUrlAnalyzer.ets)、[LocalRuleBrowserRuntime.ets](../entry/src/main/ets/service/rulesource/LocalRuleBrowserRuntime.ets)。

### 6. 对象、状态和辅助库仍是部分兼容

E 向脚本提供真实 `Book`、`BookChapter`、响应对象与 Java 宿主方法；`AnalyzeRule.get/put` 按章节→书籍→规则数据→来源查找或保存变量。还提供 `nextChapterUrl`、`fromBookInfo` 等阶段上下文。

简听已具备 `source/book/chapter/cache/cookie` 和部分 Java 数据类，但书籍/章节主要是变量快照与方法包装；目前没有同等的默认 `nextChapterUrl` / `fromBookInfo` 注入，也不保证完整的原生对象属性和持久化副作用。脚本库在独立 QuickJS 上下文中执行，不能依赖跨调用共享的任意 JS 全局对象。

E 的 `queryTTF` / `replaceFont`、ZIP/RAR/7z 内容读取及部分文件辅助方法在简听规则宿主中没有对应实现。它们会影响特定字体混淆源、压缩内容源，属于比模板兼容更大的专项。

E 自身也有 `RhinoClassShutter`，拦截敏感 Java/Android 类，不能描述成“允许任意 Java 和文件访问”。简听应继续使用有预算的白名单桥接；提高兼容性不需要开放任意平台能力。

### 7. 导入、搜索回退与媒体扩展

| 项目 | 差异及范围 |
| --- | --- |
| 旧版扁平源 | E 的 `ImportOldData.fromOldBookSource` 转换 `ruleSearchList`、`ruleSearchName`、`ruleBookName` 等；简听兼容的是规则组别名和紧凑规则，并无等价旧版扁平字段迁移 |
| `bookUrlPattern` | E 在搜索响应像详情页时按详情解析，空列表也有详情回退；简听没有同等分派，且参与搜索要求搜索列表、名称、地址规则齐全 |
| `checkKeyWord` | E 搜索规则有专用测试关键词；简听目前未映射该字段，应与用户输入的测试关键词区分 |
| `updateTime` | 简听导入搜索/详情字段，但通用结果映射未使用；目录的 `updateTime` 已使用。不能把三处统称为支持或不支持 |
| `coverDecodeJs` / `imageDecode` | E 的图片工具实际消费封面和正文图片解码脚本；简听通用图片链没有等价接入 |
| `downloadUrls` | E 详情可提供文件源下载地址；简听本地文件导入能力不能视为在线文件书源的完整兼容 |
| `payAction` | E 有用户触发的购买动作入口；简听没有对应通用执行/交互链。它不是自动获得付费内容的能力 |
| `subContent`、`callBackJs`、视频类型 | 此分支实际接入副内容、歌词/弹幕、事件回调、视频等扩展；超出简听当前小说/音频主要范围，不列为基础解析的首要补齐项 |
| `ruleReview`、`exploreScreen` | 不能按字段存在就认定完整可用。此分支 `ruleReview` 的访问器/转换器存在注释或空实现；`exploreScreen` 在本次核对范围内未找到有效消费链，均未计入确定能力优势 |

## 建议补齐顺序

| 优先级 | 工作 | 预期收益与验证重点 |
| --- | --- | --- |
| P1 | 修正 Base64、时区单位、缺失别名、布尔判断等明确契约差异 | 改动集中，可直接消除“同名方法能调用但结果错”的失败；保护现有简听书源，尤其已经依赖字节数组返回值的脚本 |
| P1 | 补目录 `preUpdateJs` / `formatJs`，多分页地址和分卷语义 | 提升普通小说源完整性；验证汇总顺序、去重、变量、取消和有界并发 |
| P1 | 设计并接入请求后的 `loginCheckJs`，补 `ruleContent.webJs` | 覆盖会话续期、响应修复、正文网页解析；验证原请求响应、错误响应、循环重试边界和 Cookie 隔离 |
| P2 | 请求 `js`、尖括号分页、旧源转换、搜索详情回退 | 扩大可直接导入的来源范围；避免把不识别字段静默当成功 |
| P2 | 以失败样例补 JSoup 方言、Java Pattern、JSONPath 与对象接口 | 按真实频率逐项实现，不用代码行数或方法数量充当兼容率 |
| P3 | 字体解析、压缩容器、图片解码、文件源 | 根据实际书源需求专项实现，保留文件/网络/内存预算 |
| 产品范围单独决定 | Sigma 视频、歌词/弹幕、事件交互等 | 不与普通书源兼容混在一次改动里 |

这是一组持续的兼容工作，不能靠再增加几个站点专用适配器完成。前两份轻页样本只覆盖其中很小的交集，规则跑通也不代表 Android 阅读书源已完整兼容。

## 核验记录与来源

- 当前 `legado-E` 工作树干净、与已获取的 `origin/main` 一致；对象连通性检查通过。
- 复用简听现有 `scripts/test-local-rule-templates.cjs` 装载器，只在内存中运行确定性探针，没有增加测试文件或修改应用实现。
- 确认 `base64Decode` 数组返回、解码后 `JSON.parse` 失败、`timeFormatUTC` 单位差异；同时确认 `ajaxAll` 存在，以及上述若干辅助方法当前未定义。
- 此装载器以 V8 代替原生 QuickJS，并模拟平台边界；探针只证明兼容层代码的行为，不证明真机安全预算、网络/DOM 或两端全链路结果。一条需要提取动作桥的探针受装载器桩限制，未用于判定解析器缺陷。
- 当前在线 HarmonyOS 目录已刷新，参考 [ArkTS 检索技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-development/01-application-framework/ArkTS/hmos-arkts-knowledge-retriever/SKILL.md) 的源码取证方式；书源差异结论来自两个本地项目，不来自通用平台指南。

E 源码引用中的短路径均相对于 `D:\legado-E\app\src\main\java\io\legado\app\`；完整在线源码基线为 [固定提交](https://github.com/Luoyacheng/legado-E/tree/8b87c5aba4df91c39a3a0939a68a1180b9f2ee1c)。
