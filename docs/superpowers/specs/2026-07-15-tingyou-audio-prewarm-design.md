# 听友源冷启动播放修复设计

## 背景

听友源的首页、书籍详情和章节目录来自静态 CDN，播放地址则必须先取得 guest token，再调用动态接口 `/api/play_token`。原生 `/api/me` 当前可能返回 401 或 5xx，因此冷启动通常需要隐藏 WebView 加载站点并从 localStorage 读取 token。

2026-07-13 的提交 `eb6870d` 在 `AudioService` 增加了 15 秒音频地址解析硬超时。实测冷浏览器会话约 17.7 秒才完成 `/api/me`，晚于外层截止时间；外层 Promise 超时后不会取消底层 WebView 任务，于是出现“先提示拿不到播放地址，稍后又恢复”的现象。重装会清空 WebView 缓存，清除下载会移除本地文件旁路，两者只会提高触发概率。

## 目标

- 进入听友书籍后按需后台预热 token，不阻塞页面和应用初始化。
- 播放、预加载和下载并发发生时只执行一次 token 获取。
- 冷启动播放不再被通用 15 秒超时误杀。
- 其他书源维持现有超时和加载行为。
- 保留隐藏 WebView 按需挂载，未使用听友源时不增加网络和内存开销。
- 日志能区分 token、动态 API、WebView 和最终播放解析阶段，但不记录 token 或响应正文。

## 非目标

- 不持久化 guest token。站点 token 有过期和撤销语义，仍由运行期会话管理。
- 不改变听友加解密协议、章节模型或下载数据结构。
- 不全局启动 ArkWeb，也不重构其他内置书源。

## 方案

### 1. 内置书源能力声明

在 `IBuiltInSource` 增加两个可选能力：

- `prepareAudio?(): Promise<void>`：后台准备播放所需会话。
- `audioResolveTimeoutMs?: number`：该书源允许的音频解析总等待时间。

`BuiltInDispatcher` 和 `BookSourceService` 负责能力分发。未声明能力的书源保持当前行为，默认超时仍为 15 秒。听友源声明 35 秒解析超时；该值覆盖已观测的约 19 秒冷启动链路并保留网络抖动余量，同时避免无限等待。

### 2. 听友 token single-flight

新增一个小型、可测试的 `AsyncSingleFlight<T>` 工具。相同实例在任务进行期间复用同一个 Promise，任务成功或失败后自动释放，允许后续重试。

听友源使用该工具包装 token 获取：

1. 非强制请求优先返回内存 token。
2. 已有 token 获取任务时直接复用。
3. 没有任务时依次尝试原生 `/api/me` 和隐藏 WebView。
4. 成功后只写入内存；失败返回空值并释放 single-flight。
5. 401 触发一次强制刷新；并发的强制刷新仍复用同一任务。

动态 API 按状态分类处理：

- 200：解密并返回。
- 401：刷新 token 后重试一次。
- 5xx 或网络异常：保留当前 token，重试请求一次，不清空有效会话。
- 其他 4xx：直接失败，不做无意义的 token 刷新。
- token 为空：不发送必然失败的未鉴权 `/api/play_token`。

### 3. 按需预热入口

`AudioService` 提供 `prewarmBookSource(book)`，内部异步调用 `BookSourceService.prepareAudioSource`，自身立即返回并统一记录失败。

以下位置在拿到书籍对象后触发预热：

- `BookDetailPage`：同步缓存命中和异步加载完成时。
- `PlayerPage`：缓存预填和异步恢复完成时。
- `EntryAbility.bootstrapAudioService`：恢复上次播放书籍后；只发起后台任务，不纳入 5 秒初始化等待。

入口允许重复调用，由 single-flight 保证实际鉴权只执行一次。删除下载不触碰 token；删除后在线播放直接复用预热结果。

### 4. 超时所有权

`AudioService.resolveAudioUrlWithTimeout` 根据书源能力选择超时：

- 默认书源：15 秒。
- 听友源：35 秒。

超时只约束用户本次播放等待，不改变底层 HTTP/WebView 自身的安全超时。后台预热通常会在点击前完成，因此 35 秒只是冷启动、卡片直达等场景的兜底上限。

### 5. WebView 首挂载保护

`WebViewAudioExtractor.onPageEnd` 忽略空 URL 和 `about:blank`，避免隐藏 Host 首次挂载或任务结束清理页面时误把空页当作目标页。暂不做严格 URL 相等校验，以免破坏站点的同源或跨域重定向。

## 数据流

1. 页面或冷启动恢复得到听友书籍。
2. `AudioService.prewarmBookSource` 触发 `prepareAudio()`，页面继续渲染。
3. 听友源开始 single-flight token 获取。
4. 用户点击播放时，`getAudioUrl` 复用内存 token 或正在进行的任务。
5. `/api/play_token` 返回签名音频 URL。
6. `AudioService` 缓存并交给 AVPlayer；下载解析走同一 token 会话。

## 错误处理与可观测性

- 日志记录 endpoint、HTTP 状态、尝试次数、获取方式和耗时。
- 日志不得输出 Authorization、token、加密请求体或解密响应正文。
- 预热失败不弹提示；实际播放仍会重试并沿用现有用户提示。
- 解析结果仍为 `tingyou://` 时视为失败，不交给 AVPlayer。
- single-flight 失败后必须释放，下一次进入页面或点击播放可以重新尝试。

## 测试与验证

### 单元测试

- 两个并发调用只执行一次底层任务，并取得相同结果。
- 底层任务失败后 single-flight 会释放，下一次调用能够成功重试。
- 默认书源保持 15 秒，听友源读取 35 秒能力值。

### 构建验证

- 运行 ArkTS/Hvigor 构建，确认接口可选字段、Promise 泛型和页面调用均能通过编译。
- 运行现有 Hypium 单元测试并加入新的 single-flight 测试套件。

### 场景验证

- 重装后首次进入听友书籍，等待预热后点击播放。
- 重装后立即从卡片或历史记录播放，允许走 35 秒兜底。
- 清除单章、整本和全部下载后在线播放。
- 快速连续点击章节，同时触发预加载或整本下载，确认只启动一次 token 获取。
- 模拟 `/api/me` 401、动态 API 5xx 和 WebView token 获取失败，确认重试边界与提示正确。
- 首次挂载隐藏 WebView 和任务结束回到 `about:blank` 时，不会提前执行目标页表达式。

## 涉及文件

- `entry/src/main/ets/service/builtin/IBuiltInSource.ets`
- `entry/src/main/ets/service/builtin/BuiltInDispatcher.ets`
- `entry/src/main/ets/service/builtin/sources/TingYouFM.ets`
- `entry/src/main/ets/service/builtin/WebViewAudioExtractor.ets`
- `entry/src/main/ets/service/BookSourceService.ets`
- `entry/src/main/ets/service/AudioService.ets`
- `entry/src/main/ets/entryability/EntryAbility.ets`
- `entry/src/main/ets/pages/BookDetailPage.ets`
- `entry/src/main/ets/pages/PlayerPage.ets`
- `entry/src/main/ets/utils/AsyncSingleFlight.ets`
- `entry/src/test/AsyncSingleFlight.test.ets`
- `entry/src/test/List.test.ets`
