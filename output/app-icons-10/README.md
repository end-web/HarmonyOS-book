# 简听 · 十款图标

本套素材由本地 Python / Pillow / NumPy 程序绘制，并非 AI 图片模型生成。

打开“总览.png”可对比十款效果。每款子目录均包含与当前项目一致的资源：

- app_icon_foreground.png：1024×1024 RGBA 透明前景。
- app_icon_background.png：1024×1024 RGBA 全不透明背景。
- app_icon_legacy.png：1024×1024 RGBA 合成图。
- app_icon.json：当前项目 layered-image 资源引用格式。

风格顺序：01 几何、02 拟物、03 珐琅、04 水墨、05 黏土、06 磨砂玻璃、07 折纸、08 木雕、09 刺绣、10 复古搪瓷。

主题是书本与耳机、声波，借鉴参考图的材质、厚度和柔和阴影，不使用参考中的第三方品牌标识。背景铺满画布，不预先裁成圆角；透明前景可由系统按图标形状裁切。

选用时可将某款目录的四个文件分别复制到 AppScope/resources/base/media 与 entry/src/main/resources/base/media。本次仅交付候选素材，未替换当前应用资源。

render_icons.py 为可复现的绘制源码。设计规格.md 记录初始设计方向，最终效果请以总览和实际 PNG 为准。
