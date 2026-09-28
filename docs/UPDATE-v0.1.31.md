# 简听 v0.1.31 邀测更新说明

## 本次更新

- 书源本地 JSON 导入支持多选，每次最多 10 个文件，单文件 2 MiB、合计 10 MiB，每批最多处理 1000 个书源。
- 串行读取文件，后台任务解析 JSON，主线程分段恢复书源模型，减少批量导入时的界面阻塞和内存占用。
- 显示文件处理进度与导入结果汇总；无效、超限文件跳过，单文件失败不阻断后续文件，继续保护锁定书源。

## 版本与验证

- 包名 `com.huan.listenbook`，版本 `0.1.31` / `1000031`，最低 API 20，目标 API 26。
- 新增导入服务 ArkTS 检查通过；文件数量/大小/总量、短读、串行句柄、坏文件、锁定书源、写入失败隔离和主线程让出回归通过。
- 使用正式 Release SDK `26.0.0.105`；实机调试 HAP 已覆盖安装到 VYG-AL00 并成功启动。
- 正式 APP 构建通过，包内核验 `apiReleaseType=Release`、`buildMode=release`、`debug=false`、最低 API 20、目标 API 26、phone 设备类型；APP 签名中内嵌 Profile 为 release，包名匹配。已生成 APP/HAP 的 SHA-256 文件。
- 实机安装启动不代表已完成多选导入性能和完整内容链路回归，邀测请重点体验文件多选、超限提示、部分成功及导入期间的界面响应。

## 安装包

- `artifacts/releases/v0.1.31/JianTing-v0.1.31-AppGallery.app`：正式发布签名邀测包，用于上传 AppGallery Connect。
- `artifacts/releases/v0.1.31/JianTing-v0.1.31-device.hap`：已授权实机使用的调试签名安装包。
- 同目录保留 SHA-256 校验文件。本次仅生成邀测包，未上传或提交平台。

打包参考：[在线邀测发布工作流](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/05-lanunch-and-distribute/hmos-connect-api-cli-skill/references/workflows.md)；安装参考：[设备验证技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-studio-verify/SKILL.md)。
