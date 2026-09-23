# 简听 v0.1.30 邀测更新说明

日期：2026-09-23。版本号：`0.1.30`，版本代码：`1000030`。本说明汇总基于提交 `0b2186f` 的本次改动。

## 新增与优化

### 电子书朗读

- 新增自定义 HTTP 朗读引擎，支持选择 JSON 文件或粘贴配置、切换音色、删除配置和记住选择；支持轻页百度 POST 模板及起点 JSON POST 音色。
- 每次最多导入 5 个文件，单文件不超过 1 MiB，最多保存 100 项配置；删除当前配置后回退系统语音。
- 合并同段短句，复用播放器并预取后两个片段，减少连续朗读等待；暂停、切章、切换音色或语速时清理旧预取。
- 朗读高亮改为自然段整体高亮，正文跟随按实际朗读句定位；优化“听”字入口、引擎选择胶囊和加载提示。

### 书架与阅听记录

- 长按书卡选择“管理”进入多选，支持当前分类全选，以及“仅删除书架”或“删除书架及本地”。网格与列表切换保留选择。
- 删除本地内容时同步清除关联的阅读、播放、朗读进度及阅听记录；仅移出书架保留相关数据。正在播放的书籍先停止播放，避免进度回写。
- 阅读记录先显示已有内容，再后台尝试从搜索缓存、旧书籍索引和正文缓存恢复缺失书籍信息；单本恢复失败不阻塞记录页。

### 书源与内容加载

- 首页来源支持已启用且具有发现规则的小说源和听书源。
- 听友统一使用用户导入的通用规则，移除专用适配、旧内置实现及注册入口；不再注入固定分类或自动改写专用接口。
- 扩展轻页规则兼容：页码候选地址、CSS 索引、JSON 路径、部分 Java 正则、响应头访问、音频直链和受控网页音频提取。
- 增加受限运行时中的 ChaCha20-Poly1305 兼容，完善显式会话的来源/域隔离，以及跨域跳转的请求头处理。
- 修复来源置顶、锁定、启停、分组、测试结果和编辑后的即时刷新；连续排序操作使用当前行号。导入来源按文件顺序排在未置顶区域前方。
- 详情页展示源返回的最新更新时间，简介清除 HTML 标签和实体残留并保留换行；补充书籍及章节元数据缓存。

### 播放与其他界面

- M4A/M4B/MP4/MOV 使用普通网络播放，以支持快速读取尾部索引；HLS/直播保持在线续流。
- 关于页新增“技术与支持”页面，展示技术支持与赞助名单；同步维护相关资源文案和产品说明。

## 兼容性与边界

- 包名保持 `com.huan.listenbook`，最低 HarmonyOS 6.0 / API 20，目标 API 26，仅面向手机。
- 听友现在依赖导入规则的完整性；旧定义若依赖专用适配，需要更新源规则。
- 自定义在线朗读依赖配置服务的可用性；导入失败或播放失败会提示错误，播放失败保留音色及位置以便重试。
- Java 正则和网页脚本属于有界兼容范围，不保证与其他阅读器完全等价；不新增漫画阅读、段评或 EPUB 原版图文排版能力。

## 构建与验证

- 使用正式 Release SDK `26.0.0.105`，发布 Profile，`assembleApp` / `buildMode=release` 构建成功。
- APP 内 HAP 元数据核验通过：`apiReleaseType=Release`、`buildMode=release`、`debug=false`、最低 API 20、目标 API 26、设备类型 phone；前景/背景图标均为 1024×1024。
- QuickJS HAR 元数据确认为同版 Release SDK、最低 API 20、目标 API 26。
- 以下 11 个 Node 回归脚本全部通过：`custom-tts`、`http-tts-prefetch`、`text-to-speech`、`shelf-batch-delete`、`rule-source-management`、`local-rule-chacha`、`local-rule-sessions`、`light-source-rules`、`source-loading`、`text-content-cache`、`audio-commands`（文件均为 `scripts/test-<名称>.cjs`）。
- 独立 ArkTS 静态检查工具初始化后超时，未取得独立检查结果；完整 Release 构建的 ArkTS 编译通过。构建仍有弃用接口、异常处理等警告。
- 本次未执行真机端到端验证。邀测重点：导入→测试→搜索→详情→阅读/播放、朗读跨章和后台控制、暂停续播及下载导出、阅读位置恢复、书架批量删除、首页刷新及空源状态。

## 邀测包

产物：`artifacts/releases/v0.1.30/JianTing-v0.1.30-AppGallery.app`；同目录附 `.sha256` 校验文件。该 APP 用于上传 AppGallery Connect 邀请测试，本次仅生成包，未上传或提交平台。安装包及本机签名配置不纳入 Git。

打包依据：[在线邀测与发布技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/06-lanunch-and-distribute/hmos-connect-api-cli-skill/SKILL.md)及其[构建工作流](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/06-lanunch-and-distribute/hmos-connect-api-cli-skill/references/workflows.md)。本次执行本地构建与产物核验，未执行平台分发工作流。
