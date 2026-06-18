#!/usr/bin/env python3
"""
生成阅读页内置字体子集(思源宋体/黑体 → GB2312 子集 woff2)。

为什么需要:Reader Kit 的自定义字体必须提供真实字体文件(fontPath + resourceRequest 回传字节),
通用族名(serif/sans-serif)无效;且 ReaderSetting.fontWeight 官方"暂不支持",粗细只能靠不同字重的
字体文件实现。完整 Noto CJK 单字重 ~10-25MB 过大,这里裁剪到 GB2312(覆盖 ~99.7% 现代中文)压到 ~3MB。

依赖: pip install fonttools brotli
源字体: Google Noto CJK(OFL-1.1),可用系统自带的 NotoSerifSC-VF.ttf / NotoSansSC-VF.ttf,
        或从 https://github.com/notofonts/noto-cjk 下载可变字体。

输出: entry/src/main/resources/rawfile/fonts/
  NotoSerifSC-Regular.woff2 / NotoSerifSC-Bold.woff2 / NotoSansSC-Bold.woff2
"""
import os
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.ttLib import TTFont
from fontTools.subset import Subsetter, Options

# 改成你的可变字体源路径
SERIF_VF = os.environ.get("NOTO_SERIF_VF", "NotoSerifSC-VF.ttf")
SANS_VF = os.environ.get("NOTO_SANS_VF", "NotoSansSC-VF.ttf")
OUT_DIR = os.environ.get("OUT_DIR", ".")

# GB2312 汉字 + 常用标点/拉丁/全角等
chars = set()
for hi in range(0xA1, 0xF8):
    for lo in range(0xA1, 0xFF):
        try:
            chars.add(bytes([hi, lo]).decode("gb2312"))
        except Exception:
            pass
unicodes = set(ord(c) for c in chars)
for a, b in [(0x20, 0x7E), (0xA0, 0xFF), (0x2010, 0x206F), (0x2150, 0x218F),
             (0x2460, 0x24FF), (0x25A0, 0x25FF), (0x2600, 0x26FF),
             (0x3000, 0x303F), (0x3040, 0x30FF), (0xFE30, 0xFE4F), (0xFF00, 0xFFEF)]:
    unicodes.update(range(a, b + 1))


def build(src: str, wght: int, out: str) -> int:
    t = TTFont(src)
    instantiateVariableFont(t, {"wght": wght}, inplace=True)
    o = Options()
    o.flavor = "woff2"
    o.desubroutinize = True
    o.layout_features = ["*"]
    o.name_IDs = ["*"]; o.name_legacy = True; o.name_languages = ["*"]
    ss = Subsetter(options=o)
    ss.populate(unicodes=unicodes)
    ss.subset(t)
    path = os.path.join(OUT_DIR, out)
    t.save(path)
    return os.path.getsize(path)


if __name__ == "__main__":
    print("codepoints:", len(unicodes))
    for src, w, out in [
        (SERIF_VF, 400, "NotoSerifSC-Regular.woff2"),
        (SERIF_VF, 700, "NotoSerifSC-Bold.woff2"),
        (SANS_VF, 700, "NotoSansSC-Bold.woff2"),
    ]:
        sz = build(src, w, out)
        print(f"{out:28s} {sz/1024/1024:5.2f} MB")
