#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
调整应用发布素材尺寸
- 截图：裁剪/缩放到 720x1280 (9:16)
- 图标：缩放到 216x216 和 1024x1024

用法：
1. 直接运行：自动找当前目录下的 raw_*.png（按文件名排序），输出 screenshot_{n}_720x1280.png
2. 仍兼容老的命名 screenshot_1_detail.png / screenshot_2_home.png ...
"""

import sys
import io
import glob
from PIL import Image
import os

# Windows 控制台 UTF-8
if sys.platform == "win32":
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")


def resize_screenshot(input_path, output_path, target_size=(720, 1280)):
    """先按宽度缩放到 720，超出 1280 高度的居中裁剪。"""
    img = Image.open(input_path)
    print(f"原始尺寸: {img.size}")

    scale = target_size[0] / img.width
    new_height = int(img.height * scale)
    img_resized = img.resize((target_size[0], new_height), Image.Resampling.LANCZOS)
    print(f"缩放后:   {img_resized.size}")

    if new_height > target_size[1]:
        top = (new_height - target_size[1]) // 2
        img_cropped = img_resized.crop((0, top, target_size[0], top + target_size[1]))
        print(f"裁剪后:   {img_cropped.size}")
        img_cropped.save(output_path, "PNG", optimize=True)
    elif new_height < target_size[1]:
        # 高度不够则居中贴在白底上
        canvas = Image.new("RGB", target_size, (255, 255, 255))
        canvas.paste(img_resized, (0, (target_size[1] - new_height) // 2))
        canvas.save(output_path, "PNG", optimize=True)
        print(f"补底后:   {canvas.size}")
    else:
        img_resized.save(output_path, "PNG", optimize=True)

    size_kb = os.path.getsize(output_path) / 1024
    print(f"输出大小: {size_kb:.1f}KB\n")


def resize_icon(input_path, output_path, size):
    img = Image.open(input_path)
    img_resized = img.resize((size, size), Image.Resampling.LANCZOS)
    img_resized.save(output_path, "PNG", optimize=True)
    size_kb = os.path.getsize(output_path) / 1024
    print(f"图标 {size}x{size}: {size_kb:.1f}KB")


def collect_inputs():
    """优先取 raw_*.png；没有时回退到旧命名。"""
    raws = sorted(glob.glob("raw_*.png"))
    raws = [p for p in raws if "raw_check" not in p and "raw_wake" not in p]
    if raws:
        return raws

    legacy = [
        "screenshot_1_detail.png",
        "screenshot_2_home.png",
        "screenshot_3_detail2.png",
        "screenshot_4_list.png",
    ]
    return [p for p in legacy if os.path.exists(p)]


if __name__ == "__main__":
    print("=" * 50)
    print("处理应用截图 (720x1280)")
    print("=" * 50)

    inputs = collect_inputs()
    if not inputs:
        print("未找到 raw_*.png 或老命名截图，跳过截图处理。")
    else:
        print(f"待处理截图：{inputs}\n")
        for i, src in enumerate(inputs, 1):
            output = f"screenshot_{i}_720x1280.png"
            print(f"处理: {src} -> {output}")
            resize_screenshot(src, output)

    print("=" * 50)
    print("处理应用图标")
    print("=" * 50)

    if os.path.exists("icon_1254x1254.png"):
        print("生成 216x216 图标...")
        resize_icon("icon_1254x1254.png", "icon_216x216.png", 216)
        print("生成 1024x1024 图标...")
        resize_icon("icon_1254x1254.png", "icon_1024x1024.png", 1024)

    print("\n处理完成。")
