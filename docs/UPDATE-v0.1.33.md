# 简听 v0.1.33 邀测更新说明

## 本次更新

- 调整“我的”账号卡片布局，增加国庆勋章，统一背景、圆角和入口箭头。
- “账号与备份”页新增独立勋章列表，放大展示勋章，下方日期为 `2026.10.01`。
- 优化圆形头像边缘与缩放显示，API 23 起开启图片边缘抗锯齿，旧系统保留圆角与插值处理。
- 包含当前工作区的阅读设置、主题与字体、音量键翻页、播放自动定时及换源筛选调整。

## 版本与验证

- 版本 `0.1.33` / `1000033`，包名 `com.huan.listenbook`，最低 API 20、目标 API 26，仅支持 phone。
- 使用 Release SDK `26.0.0.105` 和既有发布签名构建 APP；实机使用独立的调试签名 HAP。
- 最新 HAP 已在 HUAWEI Mate 80 安装启动；这不代表完整功能链路及所有视觉效果已完成实机回归。
- 定向回归通过：阅读偏好、阅读进度、段落排版、换源、28 项音频控制检查。
- APP 包内核验版本、Release SDK 渠道、release 构建模式、非调试标记、phone 类型、1024px 分层图标、勋章资源及日期；内嵌 Profile 为 release，包名匹配。
- QuickJS HAR 元数据为 Release SDK `26.0.0.105`、最低 API 20、目标 API 26。

## 交付文件

- `artifacts/releases/v0.1.33/JianTing-v0.1.33-AppGallery.app`：上传 AppGallery Connect 的正式签名邀测包。
- `artifacts/releases/v0.1.33/JianTing-v0.1.33-device.hap`：已授权实机使用的调试签名安装包。
- 同目录包含 SHA-256 校验文件、更新说明、构建与回归日志。此次仅生成包，未上传或提交平台。

打包参考：[在线邀测发布工作流](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/05-lanunch-and-distribute/hmos-connect-api-cli-skill/references/workflows.md)。本次执行本地构建、安装和包核验。
