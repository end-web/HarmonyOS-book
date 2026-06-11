# ListenBook（听书）

纯血鸿蒙多源听书 App，从旧 RN/H5 迁移而来。形态：**手机端 + 用户自带书源（无内置源）**，TV/Pad 与下载离线暂不做。

## 技术基线

- HarmonyOS Next，`compatibleSdkVersion = 6.1.0(23)`，stage 模式
- 单 module：`entry/`（type=entry，deviceTypes=phone）
- ArkUI 使用 **V2 装饰器**（`@ComponentV2`/`@Local`/`@Param`/`@Event`/`@ObservedV2`/`@Trace`）
- `bundleName`: `com.ylwang.listenbook`
- 后台模式：`audioPlayback` + `KEEP_BACKGROUND_RUNNING`
- 网络：`INTERNET`；体感：`VIBRATE`

## 目录约定（与实际一致）

```
entry/src/main/ets/
├── entryability/         # UIAbility 入口（EntryAbility）
├── entrybackupability/   # 备份扩展（EntryBackupAbility）
├── pages/                # 路由页面（Index/MainPage/PlayerPage/BookDetailPage/...）
├── components/           # 可复用组件（MiniPlayer / BookCard / FloatingTabBar）
├── service/              # 业务服务（注意：单数）
│   ├── http/             # HttpClient
│   ├── js/               # JSExecutor（书源 JS 沙箱）
│   └── rule/             # 书源规则引擎（RuleAnalyzer/AnalyzeRule/JSONPath/SimpleCSSSelector）
├── model/                # 数据模型（Book/BookSource/PlayerState）
├── theme/                # 颜色/字号/间距常量（AppColor/AppFont/AppSpace/AppRadius）
└── utils/                # 工具（WindowUtils/BookDataSource/SearchCache/...）
```

> 注：CLAUDE.md 历史版本曾写过 `services/` `models/` `viewmodels/`，与代码不符。以本文为准：实际是单数 `service/` `model/`，**没有** `viewmodels/` 层（页面直接持 `@Local` + Service 单例）。

## 核心服务

| 服务 | 职责 |
|---|---|
| `AudioService` | AVPlayer 单例，焦点管理（SHARE/INDEPENDENT、duck/打断/续播）、idle session 释放、睡眠定时器 |
| `AVSessionService` | 锁屏/控制中心媒体卡片，封面缓存，播放控制回调 |
| `BackgroundTaskService` | 注册 `audioPlayback` 长时任务，`wantAgent` 拉起 |
| `BookSourceService` | 用户订阅书源的 CRUD、启用/禁用 |
| `SourceDataService` | 用书源规则抓取并解析数据（搜索/详情/章节/正文/音频 URL） |
| `DataService` | 收藏/历史/书架本地数据 |
| `PreferenceService` | 偏好持久化（焦点模式、续播策略、默认 Tab 等） |
| `TTSService` | 文本转语音（文本阅读模式） |

## 开发约定

- 命名：页面 `XxxPage.ets`，组件 `XxxComp.ets`，Service `XxxService.ets`
- 状态：页面 `@Local` + Service 单例；不混用 V1/V2
- 列表：长列表用 `LazyForEach`（参考 `BookDataSource` / `ParagraphDataSource`），禁止 index 作为 key
- 搜索：**多源并行**聚合（不做单选），见 `SearchCache`
- 文案：UI 文案改字符串即可，不要联动改对应 `.ets` 文件名 / 类名

## Skills（在 `.claude/skills/`）

| skill | 用途 |
|---|---|
| `hmos-arkts-syntax-checker` | 编译 + 语法/错误循环修复（出 HAP/App） |
| `hmos-arkts-deprecated-interface-checker` | 扫描废弃 SDK 接口并给迁移方案 |
| `hmos-arkts-knowledge-retriever` | 检索 ArkTS 语言指南文档 |
| `hmos-arkui-develop-skill` | 写 / 审查 ArkUI 组件，含布局/动画/路由/MVVM |
| `hmos-arkui-statemgt-migration` | V1 → V2 状态管理迁移 |

## 常用命令

```bash
ohpm install
hvigorw assembleHap --mode module -p product=default     # debug
hvigorw assembleHap --mode module -p product=release     # release
hvigorw clean
```

## 当前进度

- [x] 模板初始化、签名（debug + release）
- [x] 首页 / 书架 / 书源 / 我的 四 Tab
- [x] 播放器页（控制条、章节列表、进度、自定义转场）
- [x] 详情页 / 历史 / 导入 / 设置 / 关于
- [x] 多源订阅、规则引擎（CSS/JSONPath/JS）、多源并行搜索
- [x] AudioService 焦点策略、AVSession 媒体卡片、后台播放
- [x] 文本阅读模式 + TTS
- [x] 本地播放进度持久化（恢复"上次播放"）
- [ ] 首启隐私政策同意页
- [ ] 关于页隐私政策链接
- [ ] 单元测试（当前测试文件全是 hypium 模板）
- [ ] 崩溃与异常上报
