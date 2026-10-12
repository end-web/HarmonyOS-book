# 简听阅读 v0.1.51 邀测更新说明

版本：0.1.51 / 1000051。最低 HarmonyOS 6.0（API 20），目标 API 26。

## 更新内容

- 邀测期间开放全部主题图标，无需会员校验，会员同步期间也可直接切换；图标切换仍需 API 26。
- 新增莓果酒红、活力橙、石墨灰、明亮紫、透明玻璃和夜曲·白，保留绿色声波与原夜曲款；主体大小、光晕与已确认预览一致。透明玻璃资源背景无底色，实际桌面是否补底由系统启动器决定。
- 修复 AI 封面超分等设置开关加载完成后仍被禁用的问题。
- 书架右上角按钮增加沉浸光感；书籍长按菜单第二项增加“查看详情”。
- 详情页阅读与播放按钮使用更轻透的玻璃质感，并按内容收紧宽度。
- 修复小组件长后台续播时，预缓存章节播放结束后可能不继续解析、加载和预缓存的问题。

## 构建与验证

- 使用 Release SDK 26.0.0.105，release 模式构建正式 APP；包内元数据为 `apiReleaseType=Release`、`buildMode=release`、`debug=false`，最低 API 20、目标 API 26。
- APP 签名验证通过，内嵌 Profile 为 release / app_gallery，包名匹配；六款新增图标已核对打入包内。
- 会员回归 41 组通过，包含邀测期间非会员及会员同步状态下切换图标的验证。此前音频命令与预缓存回归通过；长时间后台实机场景尚未完整验收。
- 产物、SHA-256 和 AGC 上传回执位于 `artifacts/releases/v0.1.51/`，实际上传状态以该目录 manifest 和回执为准。
- 正式 APP 已上传并关联 AGC 邀请测试版本，未提交审核。上传后当前源码已恢复主题图标会员校验，已上传包仍保留邀测免费体验策略。

打包与上传参考：[AGC 发布工作流](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/05-launch-and-distribute/hmos-connect-api-cli-skill/references/workflows.md)。
