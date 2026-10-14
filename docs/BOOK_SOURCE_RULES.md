# 书源规则

书源导入与执行统一使用轻页 `wip3l/legado-harmony` 的核心，固定提交和后续同步步骤见 [轻页引擎同步](LIGHT_SOURCE_SYNC.md)。页面、书架、阅读器与播放器保持简听实现。

## 支持的定义

- 轻页兼容 JSON：`bookSourceUrl`、`bookSourceName`、`searchUrl`、`exploreUrl`、`ruleSearch`、`ruleExplore`、`ruleBookInfo`、`ruleToc`、`ruleContent`，以及轻页支持的登录、变量、脚本和媒体字段。完整原始定义保留在加密书源库，执行前由轻页原导入方法规范化。
- 轻页原生 JSON：`sourceFormat: "native"`，使用轻页 `NativeSourceSpec` / `NativeSourceService` 的定义和解析逻辑。`vars`、静态/动态菜单、模式/频道、搜索、详情、目录、正文、媒体和交互配置按轻页语义执行。设置和登录状态单独保存在加密运行状态中。
- 文件使用 UTF-8 JSON，可导入单个定义、数组或当前导入器支持的列表包装对象。单文件/订阅最大 25 MiB；不按 1000 个定义截断。本地最多 10 文件，合计 250 MiB。

原简听 `format: "jianting.source"` / `engine: "native-v1"` 格式及其请求/算子引擎已移除，新导入明确拒绝。数据库中的历史定义不自动改写、不删除用户收藏；需换成轻页支持的定义才能解析。

## 执行链

`LocalRuleSourceImportParser → LocalRuleSourceRepository → BookSourceService / LocalRulePanelService → LocalRuleDispatcher / LightSourceBridge → LightSourceCore → 轻页原规则核心`

规则组合、CSS、XPath、JSONPath、正则、URL选项、分页、登录脚本、原生源设置、图片、音频、视频和段评动作由上游核心处理，不再使用简听旧提取器、URL分析器或按站点的内容协议适配器。脚本经 `LightSourceSandbox → LocalRuleQuickJsRuntime.execute()` 在独立 taskpool 有界 QuickJS 中执行；网络动作通过受控宿主回放，网页渲染与嗅探使用轻页宿主协议。

内容结果提供正文 `content`、原始富文本 `richContent`、图片 `imageUrls`、音频地址/请求头、视频地址及段评 `interactions`；`BookSourceService.getSourceChapterContent()` 保留完整结果，既有阅读器与播放器继续消费各自字段。没有新增漫画、视频或段评页面。

## 平台与验证

书源定义、登录状态及按源+origin隔离的 Cookie 使用简听加密数据库。QuickJS保留时间、内存、栈与输入输出预算，不开放文件、数据库或无约束平台网络。网页运行使用隐私会话租约，任务结束释放；模式/筛选修改保存后通知首页刷新。

同一份规则源码不代表每个第三方源已完成真机验证；设备网页、登录、Cookie作用域、受保护图片和超过运行预算的脚本仍需具体书源验证。当前固定版本、已适配文件、回归与升级方法以同步文档和 `third_party/light-source/upstream.json` 为准。
