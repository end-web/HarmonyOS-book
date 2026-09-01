# QuickJS 本地 HAR

该目录只包含 `@devzeng/quickjs`、QuickJS 引擎及 HarmonyOS N-API 封装，不包含轻页的 GPL-3.0 书源实现。

当前模块在上游 `@devzeng/quickjs` 0.1.0 基础上增加了：

- 可配置 QuickJS heap 与 stack 上限；
- 使用 `JS_SetInterruptHandler` 的 `evaluateBounded`；
- pending-job 数量预算；
- `arm64-v8a` 与 `x86_64` 双 ABI 构建。

使用 API 26 DevEco Studio 工具链重建并同步本地依赖：

```powershell
.\scripts\build-quickjs.ps1
```

主项目通过 `entry/libs/quickjs.har` 消费产物，不需要在根 `build-profile.json5` 注册 quickjs 模块。
业务代码只能通过 `LocalRuleQuickJsRuntime` 调用 `evaluateBounded`，不得直接调用不受限的 `evaluateScript`。

许可证和来源见根目录 `THIRD_PARTY_NOTICES.md` 及本目录的许可文件。
