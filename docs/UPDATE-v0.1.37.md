# 简听 v0.1.37 邀测更新说明

## 本次更新

- 全网榜单扩展为五个平台共 30 个榜单，完善榜单解析、切换和展示。
- 新增独立成就页，调整账号与个人页入口。
- 阅读图片背景新增自适应、平铺、拉伸和裁剪模式，保存并恢复背景偏好。
- 书源搜索链路失败时补测已启用的发现/阅读链路，保留错误原因并准确标记部分可用。
- 优化首页、播放器封面与阅读设置展示，同步使用文档和回归脚本。

## 版本与交付

- 版本 `0.1.37` / `1000037`，包名 `com.huan.listenbook`，最低 API 20、目标 API 26，仅 phone。
- 使用 Release SDK `26.0.0.105` 与既有发布签名构建。
- ArkTS 静态检查无错误；榜单、阅读偏好、书源健康回退、封面优先级与成就共 5 组定向回归通过。
- APP 构建、签名及包内元数据核验通过，内嵌 Profile 为 release；构建仍有兼容性、弃用接口和异常处理等警告。
- 邀测包：`artifacts/releases/v0.1.37/JianTing-v0.1.37-AppGallery.app`。
- 构建日志、核验结果、提交号与 SHA-256 随包保存；实际验证结果以该目录记录为准。
- 本次仅生成本地邀测包；未上传 AGC，未执行完整真机端到端回归。

打包参考：[在线邀测发布工作流](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/05-lanunch-and-distribute/hmos-connect-api-cli-skill/references/workflows.md)。
