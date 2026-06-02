# ListenBook（听书）

纯血鸿蒙多源听书 App，支持用户自定义书源订阅、多源并行搜索、音频播放与文本阅读。

## 功能特性

- 📚 **多源聚合** - 支持用户订阅多个书源，搜索时自动并行聚合所有书源结果
- 🔊 **音频播放** - 基于 AVPlayer 的音频播放，支持锁屏控制、后台播放
- 📖 **文本阅读** - 内置 TTS 文本转语音，支持文本阅读模式
- ⏯️ **播放控制** - 睡眠定时、播放速度调节、章节切换
- 💾 **数据持久化** - 收藏、历史记录、播放进度本地保存
- 🎨 **主题适配** - 支持深色/浅色模式

## 技术栈

- **平台**: HarmonyOS Next (Stage 模式)
- **SDK**: compatibleSdkVersion 6.1.0(23)
- **UI**: ArkUI + V2 状态管理 (@ComponentV2 / @Local / @Param / @ObservedV2 / @Trace)
- **语言**: ArkTS (TypeScript)
- **设备**: 手机端

## 项目结构

```
entry/src/main/ets/
├── entryability/         # UIAbility 入口
├── pages/                # 路由页面
│   ├── Index.ets         # 主框架（Tab 容器）
│   ├── HomePage.ets      # 首页（搜索 + 书架）
│   ├── SourcePage.ets    # 书源管理
│   ├── ProfilePage.ets   # 我的
│   ├── PlayerPage.ets    # 播放器
│   └── BookDetailPage.ets # 书籍详情
├── components/           # 可复用组件
├── service/              # 业务服务
│   ├── AudioService.ets  # 音频播放核心
│   ├── BookSourceService.ets # 书源管理
│   └── SourceDataService.ets # 书源数据解析
├── model/                # 数据模型
├── theme/                # 主题常量
└── utils/                # 工具类
```

## 核心服务

| 服务 | 职责 |
|---|---|
| `AudioService` | AVPlayer 单例，焦点管理、后台播放、睡眠定时器 |
| `BookSourceService` | 用户订阅书源的 CRUD、启用/禁用 |
| `SourceDataService` | 书源规则解析（CSS/JSONPath/JS） |
| `DataService` | 收藏/历史/书架本地数据 |
| `PreferenceService` | 偏好设置持久化 |

## 开发指南

### 环境要求

- DevEco Studio 5.0+
- HarmonyOS SDK 6.1.0(23)
- Node.js 18+

### 安装依赖

```bash
ohpm install
```

### 构建运行

```bash
# Debug 构建
hvigorw assembleHap --mode module -p product=default

# Release 构建
hvigorw assembleHap --mode module -p product=release

# 清理构建
hvigorw clean
```

### 开发规范

- 使用 V2 状态管理装饰器（@ComponentV2 / @Local / @Param 等）
- 长列表使用 `LazyForEach`，禁止使用 index 作为 key
- 搜索必须多源并行聚合，不做单选
- UI 文案使用字符串资源，不硬编码

## 书源格式

支持 Legado 兼容的书源格式，规则引擎支持：
- CSS 选择器
- JSONPath
- JavaScript 沙箱执行

## 许可证

MIT License

## 相关链接

- [HarmonyOS 开发文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/application-dev-guide-V5)
- [ArkUI 组件文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/ts-components-V5)
