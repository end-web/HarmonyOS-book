# ListenBook（听书）

纯血鸿蒙听书 App，从旧 RN/H5 迁移而来。当前阶段：**手机适配 + 点播闭环**为先，TV/Pad 与下载离线后续再做。

## 技术基线

- HarmonyOS Next，`compatibleSdkVersion = 6.1.0(23)`，stage 模式
- 单 module：`entry/`（type=entry，deviceTypes=phone）
- ArkUI 使用 **V2 装饰器**（`@ComponentV2`/`@Local`/`@Param`/`@Event`/`@ObservedV2`/`@Trace`）
- `bundleName`: `com.ylwang.listenbook`

## 目录约定

```
entry/src/main/ets/
├── entryability/         # UIAbility 入口
├── entrybackupability/   # 备份扩展
├── pages/                # 路由页面（Index/Player/Detail/...）
├── components/           # 可复用组件（待建）
├── viewmodels/           # 页面 VM（MVVM，待建）
├── services/             # 业务服务（播放器/接口/缓存，待建）
├── models/               # 数据模型（待建）
└── utils/                # 工具（待建）
```

## 开发约定

- 命名：页面 `XxxPage.ets`，组件 `XxxComp.ets`，VM `XxxVM.ets`，Service `XxxService.ts`
- 状态：复杂页用 MVVM；简单页直接组件内 `@Local`；不混用 V1/V2
- 列表：长列表用 `LazyForEach` + `Repeat`，禁止 index 作为 key
- 接口：统一从 `services/` 出口；字段 `camelCase`；空态/错误态在 VM 收敛
- 资源：颜色/字号/字符串走 `$r('app.xxx')`，禁止硬编码

## Skills（在 `.claude/skills/`）

会话中可按需调用：

| skill | 用途 |
|---|---|
| `hmos-arkts-syntax-checker` | 编译 + 语法/错误循环修复（出 HAP/App） |
| `hmos-arkts-deprecated-interface-checker` | 扫描废弃 SDK 接口并给迁移方案 |
| `hmos-arkts-knowledge-retriever` | 检索 ArkTS 语言指南文档 |
| `hmos-arkui-develop-skill` | 写 / 审查 ArkUI 组件，含布局/动画/路由/MVVM |
| `hmos-arkui-statemgt-migration` | V1 → V2 状态管理迁移 |

> 这些 skill 的部分能力依赖 codegenie 的 MCP 工具（`mcp_codegenie-mcp_*`）。MCP 不可用时，相关步骤会被跳过，依然可以读 references 当文档库用。

## 常用命令

```bash
# 安装依赖
ohpm install

# 构建（DevEco 命令行 hvigor）
hvigorw assembleHap --mode module -p product=default
hvigorw clean
```

## 当前进度

- [x] 模板初始化（bundle/app 名/技能搬迁）
- [ ] 首页骨架（书架 / 推荐 / 我的 三 Tab）
- [ ] 播放器页（控制条 + 章节列表 + 进度）
- [ ] 接口层（书籍列表 / 章节 / 播放鉴权）
- [ ] 本地播放进度持久化
