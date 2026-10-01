# 简听 v0.1.40 邀测更新说明

## 本次更新

- 优化封面进入详情的一镜到底交接，等待真实封面加载后再淡出转场截图。
- 扩展标准穿戴设备入口、离线书架与账号恢复链路，并调整手机、平板和 2in1 适配。
- 完善本地电子书导入、阅读位置恢复、书架更新和榜单展示。
- 增加卡通主题图标，优化现有图标与阅读勋章资源体积。

## 版本与验证

- 版本 `0.1.40` / `1000040`，最低 API 20，目标 API 26；设备声明为 phone、tablet、2in1、wearable。
- 使用 Release SDK `26.0.0.105`、`release` 构建模式和既有发布签名生成 APP；包内元数据、发布 Profile 和签名核验通过。
- 穿戴端、本地导入、榜单、阅读位置和书架更新的定向回归脚本通过；尚未完成四类设备的端到端验证，尤其未做手表硬件验证。
- 邀测包：`artifacts/releases/v0.1.40/JianTing-v0.1.40-AppGallery.app`，同目录附 SHA-256、构建日志与核验结果。仅生成本地包，未上传 AppGallery Connect。

打包参考：[在线邀测发布工作流](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/05-lanunch-and-distribute/hmos-connect-api-cli-skill/references/workflows.md)。
