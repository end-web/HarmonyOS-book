# 简听 v0.1.49 邀测更新说明

日期：2026-10-10。版本：0.1.49 / 1000049，最低 HarmonyOS 6.0（API 20），目标 API 26。

## 更新内容

- 书架支持“全部 / 连载中 / 已完结”筛选并记住选择，与分类和关键词搜索叠加使用。
- 书架搜索改为顶部按钮展开，通过原生 geometryTransition 从按钮生长为整行搜索框，收起返回原位；保留分类 Tab 沉浸效果并收紧布局。
- 优化会员权益获取和设置页加载；调整名称、会员图标及成就馆勋章布局，合并重复提示。
- 加深全网榜单搜索结果来源卡片背景，提高内容辨识度。
- 优化详情页收听记录的加载时机及历史数据处理；章节加载期间禁用收听、阅读按钮并显示加载提示。
- 增加波浪备用图标。
- 固定书籍元数据的序列化字段名，兼容旧正式包中的目录完整性、最新章节和封面字段，保留缓存及备份中的旧数据。

## 打包与验证

- 使用 Release SDK 26.0.0.105、release 编译模式和新配置的正式发布签名（app_gallery Profile），开发者会员权益开关关闭。最终 APP 的包元数据与 SDK 签名校验通过。
- 产物目录：`artifacts/releases/v0.1.49/`；签名、包元数据、SHA-256 和回归结果以同目录核验记录为准。
- 本轮界面开发版本已在 Mate 80 安装运行；正式包的支付、云服务和多设备端到端体验尚未完成实机验收。
- 仅生成本地邀测包，未上传 AppGallery Connect 或提交审核。

参考：[发布签名与 APP 构建流程](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/05-launch-and-distribute/hmos-connect-api-cli-skill/references/workflows.md)、[Hvigor 构建指导](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-studio-hvigor/SKILL.md)。
