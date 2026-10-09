# 简听 v0.1.48 更新说明

日期：2026-10-09。版本：0.1.48 / 1000048，最低 HarmonyOS 6.0（API 20），目标 API 26。

## 更新内容

- 修复点击首页搜索入口时，因空路由参数导致搜索页无法正常打开的问题。
- 完善页面参数容错：缺失或无效的搜索关键词使用空值，分类搜索继续保留预填关键词。

## 验证与打包

- 搜索路由回归通过，覆盖首页搜索、空参数、无效关键词、分类关键词及共享路由字段。
- 开发者 HAP 使用 debug 模式和调试签名，仅该包启用开发者权益；邀测 APP 使用 release 模式和正式发布签名，关闭开发者权益开关。
- 产物目录：`artifacts/releases/v0.1.48/`。构建、签名核验与设备安装结果以该目录的记录为准。
- 本次仅生成本地邀测包，不上传 AppGallery Connect 或提交审核。

打包参考：[在线 Hvigor 构建技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-studio-hvigor/SKILL.md)、[发布签名与 APP 构建流程](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/05-launch-and-distribute/hmos-connect-api-cli-skill/references/workflows.md)。
