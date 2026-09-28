# 简听 v0.1.32 邀测更新说明

## 本次更新

- 修复选择 JSON 后书源未导入：后台解析仅依赖纯 JSON 与基础库，避免加载界面状态模型触发 `Trace is not defined`。
- 修复多块读取重复叠加文件偏移导致的跳读；文件限制提升为单个 10 MiB、每批 30 MiB，最多 10 个文件、1000 个书源。
- 部分导入失败时保留结果与原因，成功后清除列表搜索、分组和状态筛选，让新书源可见。
- 音频预缓存采用串行去重队列，优先缓存当前章，再按播放方向预取邻近章节；暂停、缓冲或关闭预缓存时取消任务，改善回听复用和重复下载。
- 音频解析地址限时复用，缓存淘汰避开正在播放、下载和发布中的文件；同步相关界面、文档及回归测试。

## 版本与验证

- 包名 `com.huan.listenbook`，版本 `0.1.32` / `1000032`，最低 API 20，目标 API 26，仅支持 phone。
- 使用正式 Release SDK `26.0.0.105` 和既有发布证书生成邀测 APP。
- 正式构建通过；包内核验 `apiReleaseType=Release`、`buildMode=release`、`debug=false`、版本及 API 范围正确，APP 内嵌 Profile 为 release。QuickJS HAR 同为 Release SDK，已生成 APP 的 SHA-256 校验文件。
- `test-source-file-import.cjs`、`test-audio-preload.cjs`、`test-audio-commands.cjs` 通过，其中音频控制检查 26 项。
- 书源导入修复已在 VYG-AL00 使用真实文件读取、taskpool 和数据库通过定向测试：3 MiB JSON 和另一个有效文件成功导入，中间坏文件单独跳过，完整中文字段与管理列表查询一致。
- 上述实机定向测试验证导入修复，不代表本版全部音频、下载、导出及界面流程已完成实机回归。

## 邀测包

`artifacts/releases/v0.1.32/JianTing-v0.1.32-AppGallery.app`，同目录附 SHA-256 校验文件、更新说明和构建日志。仅生成包，未上传或提交 AppGallery Connect。

打包依据：[在线邀测发布工作流](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/05-lanunch-and-distribute/hmos-connect-api-cli-skill/references/workflows.md)。
