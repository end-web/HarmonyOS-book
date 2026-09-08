# 第三方软件声明

## @devzeng/quickjs / ohos_quickjs

- 上游项目：https://github.com/hhtczengjing/ohos_quickjs
- 版本：0.1.0（包含本项目使用的受限执行与 HarmonyOS API 26 双 ABI 修改）
- 许可证：MIT
- 版权所有：Copyright (c) 2026 zengjing

许可全文见 `third_party/quickjs/quickjs/LICENSE`。本项目保留原模块的版权、许可和免责声明。

## QuickJS JavaScript Engine

- 上游项目：https://bellard.org/quickjs/
- 许可证：MIT
- 版权所有：Copyright (c) 2017-2021 Fabrice Bellard；Copyright (c) 2017-2021 Charlie Gordon

许可全文见 `third_party/quickjs/LICENSE-QUICKJS`。

## OpenHarmony / Huawei N-API 封装代码

QuickJS 模块中带有 Huawei Device Co., Ltd. 版权头的 N-API 封装文件依据 Apache License 2.0 使用；修改后的文件继续保留原版权和许可头。

Apache License 2.0 全文见 `third_party/quickjs/LICENSE-APACHE-2.0`。

## 许可边界

本项目只引入独立的 QuickJS 和下述 CryptoJS 组件，没有复制或链接轻页应用的 GPL-3.0 书源引擎、页面或业务代码。

## CryptoJS

- 上游项目：https://github.com/brix/crypto-js
- 版本：4.2.0，仅包含 core、cipher-core、tripledes、mode-ecb 和 pad-nopadding
- 许可证：MIT
- 版权所有：Copyright (c) 2009-2013 Jeff Mott；Copyright (c) 2013-2016 Evan Vosberg

许可全文与固定版本信息见 `third_party/crypto-js/LICENSE` 和 `third_party/crypto-js/README.md`。仅在受限 QuickJS 中兼容用户导入书源的旧 DES／3DES 协议，不用于应用数据库、账号、Cookie 或传输加密。

运行时子集位于 `entry/src/main/ets/service/rulesource/LocalRuleLegacyCrypto.ets`，提供 DES/TripleDES 的 CBC/ECB 和显式密钥处理，继续遵循 QuickJS 的时间、内存和输出预算；不暴露模块加载、基于密码的密钥派生或原生随机数提供者。
