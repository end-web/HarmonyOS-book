# 简听上架素材

应用名称统一为 **简听**。本目录是当前中文介绍、截图和隐私政策的维护入口，旧调试截图不再作为上架素材使用。

## 介绍与图片

- [zh-CN.json](zh-CN.json)：应用名称、一句话简介、完整介绍、新版本说明及截图顺序。
- [introduction.txt](introduction.txt)：可直接复制到上架后台的纯文本介绍。
- [index.html](index.html)：公开展示页，汇总应用介绍、截图和隐私政策入口。
- [icon.png](icon.png)：1024×1024 应用图标，与安装包图标同源。
- [screenshots/](screenshots/)：简听 v0.1.13 的手机实机截图，按文件名顺序展示关于、书架、本地导入和使用说明。图片未拼接或替换界面内容。
- [privacy.html](privacy.html)：可部署的简听隐私政策网页，正文与应用内资源一致。

## 安装包

当前邀测构建版本 `0.1.28` / `1000028`（GitHub 已发布版本仍为 `0.1.27`），包名 `com.huan.listenbook`，最低 HarmonyOS 6.0 / API 20，目标 API 26。沿用原包名与签名配置，保留升级安装和已有本地数据。

- `JianTing-v0.1.27.hap`：开发签名 HAP，用于获授权设备安装和 GitHub 分发；对应 SHA-256 文件与本机安装包位于 `artifacts/releases/v0.1.27/`。
- `JianTing-v0.1.28-AppGallery.app`：本次正式签名邀测 APP 与校验文件位于 `artifacts/releases/v0.1.28/`，用于上传 AppGallery Connect 发起邀测；生成包不代表已提交平台。
- 最新 HAP 通过 [GitHub Releases](https://github.com/end-web/HarmonyOS-book/releases/latest) 分发。

## 平台同步

在 AppGallery Connect 的同一个应用条目中，将名称、一句话简介、介绍、新版本说明和截图替换为本目录内容，并上传新版 APP。保留应用原有标识。

公开展示页由 GitHub Pages 发布到 https://end-web.github.io/HarmonyOS-book/ ，隐私政策地址为 https://end-web.github.io/HarmonyOS-book/privacy.html 。部署成功并确认可访问后，将隐私政策地址填写到 AppGallery Connect。

软件资质中的法定软件名称也需与“简听”相对应。资质变更由发证机构或平台办理，本目录中的文案和代码改名不能代替资质变更。

## 后续维护

更新应用内隐私文案后，运行 `python scripts/export-app-gallery.py`，同步生成隐私政策网页和图标。应用内文案位于 `entry/src/main/resources/base/element/string.json`，章节顺序来自 `PrivacyPage.ets`。截图在安装当前版本后重新采集。
