# 简听阅读 v0.1.52 邀测更新说明

- 测试说明：测试图标。
- 邀测包临时开放全部主题图标；会员过期、换号、核验失败回调遵循同一权限开关，不再自动恢复默认图标。切换仍需 API 26。
- 同步当前播放、封面加载、书源远程导入与会员核验改动。
- 使用 Release SDK 26.0.0.105、release 编译模式和正式 app_gallery 签名；开发者会员开关关闭。会员回归 57 组、包元数据及签名验证通过；未进行本次实机验证。
- APP 与 AGC 上传、版本配置、核验记录位于 `artifacts/releases/v0.1.52/`，测试结束时间为北京时间 2026-10-15 23:59:59。
- 上传后本地源码恢复图标会员限制，保留失效回调遵循权限开关的修复。测试包保留开放策略；未提交审核。

参考：[AGC 邀测发布工作流](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/05-launch-and-distribute/hmos-connect-api-cli-skill/references/workflows.md)。
