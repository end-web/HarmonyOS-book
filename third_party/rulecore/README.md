# Native Rule Core

固定功能的仓颉 HTML tokenizer，通过 C ABI 和一层 NAPI 对接 ArkTS。
模块不执行书源代码，不提供网络、文件、数据库或平台对象。

## 边界

- ArkTS 负责请求、源会话、规则编排、实体解码、DOM/CSS 与业务映射。
- 仓颉 `src/tokenizer.cj` 负责标签、属性、文本、注释和 rawtext 分词。
- C++ `src/native_rulecore.cpp` 只负责参数检查、仓颉运行时及任务调度、内存释放和 NAPI 返回。
- `libnative_rulecore.so` 导出 `tokenizeHtml(html: string): string`；必须在 taskpool 工作线程调用。
- 一次调用仅接收 HTML 字符串，返回 `{ "tokens": [...], "error": "" }` JSON。失败时仓颉返回非空 error，绑定层基础设施错误抛出 `NATIVE_RULECORE`。
- open token：`type/name/attributes/selfClosing/start/end`；close token：`type/name/start/end`；text token：`type/text/start/end`。
- start/end 为 UTF-16 code unit 偏移，与 ArkTS substring 一致。文本和属性值保留原始实体，由 ArkTS 统一解码。
- `script/style/title/textarea` 只处理 rawtext，绝不执行脚本。

预算：输入最多 4 Mi UTF-16 code units、16 MiB UTF-8，输出最多 32 MiB UTF-8，最多 50,000 tokens，每个标签最多 256 属性。NAPI 使用进程级 mutex 串行化调用以限制峰值分配。仓颉运行时可能根据 OHOS 内存策略调整堆，因此这些限制是算法输入/输出预算，不能描述为 QuickJS 式独立硬堆沙箱。

## 工具链和来源

- 仓颉编译器 **1.2.0 STS**，发布于 2026-09-22。官方索引：<https://cangjie-lang.cn/download/1.2.0>。
- 官方 Windows OHOS 包：<https://cangjie-lang.cn/v1/files/auth/downLoad?nsId=142267&fileName=cangjie-sdk-windows-x64-ohos-1.2.0.exe&objectKey=6ab1eab6e4bd101f57762f5c>。
- 官方 SHA256：`6faf77a47f9d8bacad58cf1ed1a850a3179a9d843d003fe80da47972de2761f9`，下载后已核对一致。
- 包为 NSIS 自解压格式；只提取 SDK 文件到独立 `D:\soft\cangjie-1.2.0-ohos`，没有运行仓颉安装器，没有覆盖 DevEco Studio 的正式 SDK。
- HarmonyOS SDK：`D:\soft\DevEcoStudio-26.0.0-Release\sdk\default\sdk-pkg.json`，API 26、版本 `26.0.0.105`、`releaseType=Release`。
- C ABI 指南：<https://cj-docs.gitcode.com/zh/1.2.0/dev-guide/source_zh_cn/FFI/cangjie-c.html>。
- 交叉编译指南：<https://cj-docs.gitcode.com/zh/1.2.0/dev-guide/source_zh_cn/compile_and_build/cross_compilation.html>。
- `include/Cangjie.h` 与固定 v1.2.0 源码完全一致：<https://raw.gitcode.com/Cangjie/cangjie_runtime/raw/52f9e08f985ba42e23581e725e1b11f956f941d6/runtime/src/Cangjie.h>；保留原始版权与许可头。
- 初始化流程依照该头文件与官方 `runtime/src/CangjieRuntimeApi.cpp`：`InitCJRuntime` → `LoadCJLibraryWithInit` → `FindCJSymbol` → `RunCJTask` → `GetTaskRet` → `ReleaseHandle`。

本模块使用纯 C ABI，不依赖 Beta `ohos.ark_interop`。独立编译器的正式版本、Release SDK 构建、某设备成功运行均不等于已证明 API 20 或 wearable 支持。App 仍需按已验证能力选择仓颉或纯 ArkTS 实现。

## 应用运行时适配

官方 OHOS SDK 的预编译 `libcangjie-runtime.so` 依赖系统 `libc++.so` 与 `std::__h` ABI；手机应用 namespace 无法直接加载它。应用 NDK 的 `libc++_shared.so` 使用 `std::__n1`，不能改名、制作符号别名或混入旧版仓颉运行时解决。

本项目仅从仓颉 **v1.2.0** 固定 commit `52f9e08f985ba42e23581e725e1b11f956f941d6` 重编 runtime，使用上述 Release NDK 的应用 C++ ABI。官方 1.2.0 编译器、核心标准库和 tokenizer ABI 保持同版本，保留上游运行时版本兼容检查（显式 `DISABLE_VERSION_CHECK=0`，同时覆盖增量构建旧缓存）。securec 构建依赖固定为 OpenHarmony-v6.0-Release commit `2ae82839ecaaa7d031e66ccbd2076d671acfd615`；随包 `libboundscheck.so` 仍来自原始官方仓颉 SDK。

适配逻辑保存在 `tools/prepare_app_runtime.py`：调整上游工具链路径、应用 C++ 链接名和双 ABI 产物目录；唯一运行时代码改动是在 `RULECORE_APP_RUNTIME` 下将 ROM namespace 检查返回 false。随应用打包的 runtime 不属于 `cj_rom_sdk`，因此使用原有公开 `dlopen/dlsym` 路径，不调用私有 `dlns_get`，也不绕过系统 namespace 隔离。

## 构建和验证

```powershell
./scripts/build-rulecore.ps1 `
  -DevEcoRoot 'D:\soft\DevEcoStudio-26.0.0-Release' `
  -CangjieRoot 'D:\soft\cangjie-1.2.0-ohos' `
  -VerifyHost
```

脚本先调用 `scripts/build-cangjie-app-runtime.ps1`，在忽略目录 `build/` 获取并核验上述固定源码，使用现有 NDK 的 CMake/Ninja 增量构建两个 ABI。`tools/verify_app_runtime.py` 检查运行时、tokenizer、核心标准库和 NAPI 绑定的完整依赖及强符号闭包，拒绝系统 C++ ABI。随后编译核心/NAPI，将最小库集合写入 `entry/libs/<abi>` 并更新 `entry/libs/rulecore-build.json`。重复运行不会恢复不兼容的官方系统 runtime，也不修改根签名配置。

`-VerifyHost` 将同一仓颉源码编译为 Windows DLL，通过真实仓颉运行时 C ABI 执行 HTML、UTF-16、rawtext 和预算检查。它不是手机、模拟器或手表运行验证。设备成功加载日志为固定文本 `NativeRuleCore: Cangjie 1.2.0 tokenizer initialized (C ABI)`，不包含请求或 HTML 数据。

2026-10-13 最终包已在 API 26、arm64 手机 VYG-AL00 验证：保留版本兼容检查的原生库初始化成功，4 次 `tokenizeNativeHtml` taskpool 任务正常结束，耗时 36/38/20/21 ms（首轮含初始化），未见运行时版本错误或 ArkTS 回退。对应 runtime SHA256 为 `5cf19b6263f5c284ce17646101d8ebc1a90f6ac7d6b6994e2df654ea723aee3c`，构建清单保留这次设备验证记录；每次重建默认重置为待验证。x86_64 已完成构建和公共 SDK 依赖/强符号闭包检查；API 20、wearable 和 x86_64 设备实际运行尚未验证。

许可证与官方第三方声明见 `licenses/CANGJIE-LICENSE` 和 `licenses/CANGJIE-Open_Source_Software_Notice.docx`。App 随包保留相关版权归属，更新仓颉运行时必须同步更新这些文件。
