"""Create square wearable and wide PC promotional graphics from project assets."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[3]
POSTERS = Path(__file__).resolve().parent
GALLERY = ROOT / "docs" / "app-gallery"
FONT_REGULAR = "C:/Windows/Fonts/msyh.ttc"
FONT_BOLD = "C:/Windows/Fonts/msyhbd.ttc"
INK = "#202124"
MUTED = "#737478"
ROSE = "#BD455E"


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_BOLD if bold else FONT_REGULAR, size)


def centered(draw: ImageDraw.ImageDraw, x: int, y: int, text: str, fill: str, size: int,
             bold: bool = False) -> None:
    draw.text((x, y), text, fill=fill, font=font(size, bold), anchor="mt")


def shadow(canvas: Image.Image, box: tuple[int, int, int, int], radius: int, blur: int = 26) -> None:
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(box, radius=radius, fill=(36, 33, 33, 50))
    canvas.alpha_composite(layer.filter(ImageFilter.GaussianBlur(blur)))


def brand(canvas: Image.Image, x: int, y: int, icon_size: int, text_size: int) -> None:
    icon = Image.open(GALLERY / "icon.png").convert("RGB")
    icon = icon.resize((icon_size, icon_size), Image.Resampling.LANCZOS)
    canvas.paste(icon, (x, y))
    ImageDraw.Draw(canvas).text((x + icon_size + 12, y + 7), "简听", fill=INK,
                                font=font(text_size, True))


def watch_base(index: int, kicker: str, first: str, second: str, note: str,
               background: str = "#FAF7F5") -> tuple[Image.Image, ImageDraw.ImageDraw]:
    canvas = Image.new("RGBA", (840, 840), background)
    draw = ImageDraw.Draw(canvas)
    brand(canvas, 52, 45, 52, 29)
    draw.text((697, 63), f"{index:02d} / 04", fill=ROSE, font=font(22, True))
    draw.line((54, 121, 786, 121), fill="#E8E0DF", width=2)
    draw.text((55, 155), kicker, fill=ROSE, font=font(23, True))
    draw.text((49, 193), first, fill=INK, font=font(62, True))
    draw.text((49, 266), second, fill=ROSE, font=font(61, True))
    draw.text((56, 351), note, fill=MUTED, font=font(22))
    draw.text((55, 790), "界面示意", fill="#9E9B9B", font=font(17))
    draw.text((684, 790), "JIAN TING", fill=ROSE, font=font(18, True))
    return canvas, draw


def watch_screen(canvas: Image.Image) -> ImageDraw.ImageDraw:
    shadow(canvas, (325, 352, 775, 802), 225, 30)
    draw = ImageDraw.Draw(canvas)
    draw.ellipse((315, 342, 765, 792), fill="#25282A")
    draw.ellipse((331, 358, 749, 776), fill="#050505")
    draw.arc((320, 347, 760, 787), 203, 322, fill="#515557", width=5)
    return draw


def watch_button(draw: ImageDraw.ImageDraw, y: int, label: str, accent: bool = False) -> None:
    draw.rounded_rectangle((387, y, 694, y + 54), radius=23,
                           fill=ROSE if accent else "#252525")
    centered(draw, 540, y + 12, label, "#FFFFFF", 22, accent)


def watch_text(draw: ImageDraw.ImageDraw, y: int, text: str, size: int = 24,
               color: str = "#FFFFFF", bold: bool = False) -> None:
    centered(draw, 540, y, text, color, size, bold)


def save_watch(canvas: Image.Image, name: str) -> None:
    output = POSTERS / "watch"
    output.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(output / name, "PNG", optimize=True)


def make_watch() -> None:
    canvas, _ = watch_base(1, "标准手表  /  独立听书", "好故事", "抬腕接着听", "书架、搜索与播放，随时打开。")
    draw = watch_screen(canvas)
    watch_text(draw, 407, "简听", 30, bold=True)
    watch_button(draw, 466, "我的书架")
    watch_button(draw, 531, "搜索听书")
    watch_button(draw, 596, "导入书源")
    save_watch(canvas, "01-home.png")

    canvas, _ = watch_base(2, "书架  /  搜索", "想听的书", "就在手腕上", "导入书源后，搜索并收藏。", "#F7F8F7")
    draw = watch_screen(canvas)
    watch_text(draw, 396, "返回", 21, "#C6C6C6")
    draw.rounded_rectangle((386, 447, 695, 500), radius=20, fill="#252525")
    draw.text((411, 457), "书名 / 作者", fill="#AFAFAF", font=font(20))
    watch_button(draw, 515, "搜索听书", True)
    draw.rounded_rectangle((386, 584, 695, 660), radius=20, fill="#1C1C1E")
    draw.text((406, 591), "我叫赵甲", fill="#FFFFFF", font=font(22, True))
    draw.text((406, 624), "有声书", fill="#BBBBBB", font=font(17))
    save_watch(canvas, "02-search.png")

    canvas, _ = watch_base(3, "播放  /  随时继续", "喜欢的声音", "陪你走下去", "逐集播放，进度可以接着听。", "#FAF7F5")
    draw = watch_screen(canvas)
    watch_text(draw, 394, "返回", 21, "#C6C6C6")
    watch_text(draw, 445, "我叫赵甲", 29, bold=True)
    watch_text(draw, 484, "第 516 集", 20, "#BBBBBB")
    watch_button(draw, 534, "暂停", True)
    watch_text(draw, 606, "12:48 / 38:16", 18, "#BBBBBB")
    watch_button(draw, 639, "后退 15 秒")
    save_watch(canvas, "03-player.png")

    canvas, _ = watch_base(4, "下载  /  离线收听", "先下载", "再安心听", "当前集或接下来 5 集，自主选择。", "#F7F8F7")
    draw = watch_screen(canvas)
    watch_text(draw, 396, "返回", 21, "#C6C6C6")
    watch_text(draw, 445, "我叫赵甲", 28, bold=True)
    watch_button(draw, 501, "下载当前起 5 集", True)
    watch_text(draw, 571, "已完成 5 / 5 集", 20, "#C8C8C8")
    draw.rounded_rectangle((383, 615, 697, 685), radius=20, fill="#1C1C1E")
    draw.text((407, 623), "第 516 集", fill="#FFFFFF", font=font(20, True))
    draw.text((407, 652), "已下载，可离线播放", fill="#E08AA0", font=font(17))
    save_watch(canvas, "04-offline.png")


def pc_base(index: int, kicker: str, first: str, second: str, note: str,
            background: str) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    canvas = Image.new("RGBA", (1920, 1080), background)
    draw = ImageDraw.Draw(canvas)
    brand(canvas, 117, 49, 60, 33)
    draw.text((1687, 72), f"{index:02d} / 03", fill=ROSE, font=font(26, True))
    draw.line((120, 137, 1800, 137), fill="#E6DFDD", width=2)
    draw.text((127, 251), kicker, fill=ROSE, font=font(27, True))
    draw.text((116, 307), first, fill=INK, font=font(82, True))
    draw.text((116, 424), second, fill=ROSE, font=font(80, True))
    draw.text((126, 574), note, fill=MUTED, font=font(30))
    draw.line((120, 994, 1800, 994), fill="#E6DFDD", width=2)
    draw.text((123, 1014), "简听  /  PC · 2in1", fill=MUTED, font=font(23))
    draw.text((1600, 1014), "界面示意", fill="#999596", font=font(22))
    return canvas, draw


def app_window(canvas: Image.Image, page: str, sidebar: bool = True) -> ImageDraw.ImageDraw:
    shadow(canvas, (760, 245, 1810, 914), 25, 30)
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((750, 222, 1818, 922), radius=27, fill="#292D2F")
    draw.rounded_rectangle((761, 234, 1807, 910), radius=18, fill="#FBFBFB")
    draw.rounded_rectangle((761, 234, 1807, 297), radius=18, fill="#F3F3F3")
    draw.rectangle((761, 275, 1807, 297), fill="#F3F3F3")
    draw.text((792, 251), "简听", fill=INK, font=font(22, True))
    draw.text((1665, 254), "－  □  ×", fill="#7B7C7D", font=font(24))
    if sidebar:
        draw.rectangle((761, 297, 956, 909), fill="#F3F3F3")
        for y, label in ((360, "首页"), (422, "书架"), (484, "记录"), (546, "我的")):
            active = label == page
            if active:
                draw.rounded_rectangle((781, y - 9, 935, y + 43), radius=13, fill="#F6E7EB")
            draw.text((810, y), label, fill=ROSE if active else "#66676A",
                      font=font(22, active))
    return draw


def book_cover(canvas: Image.Image, box: tuple[int, int, int, int], source_box: tuple[int, int, int, int]) -> None:
    original = Image.open(GALLERY / "screenshots" / "02-library.png").convert("RGB")
    cover = original.crop(source_box)
    left, top, right, bottom = box
    cover = ImageOps.fit(cover, (right - left, bottom - top), Image.Resampling.LANCZOS)
    mask = Image.new("L", cover.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, cover.width, cover.height), radius=13, fill=255)
    canvas.paste(cover, (left, top), mask)


def save_pc(canvas: Image.Image, name: str) -> None:
    output = POSTERS / "pc"
    output.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(output / name, "PNG", optimize=True)


def make_pc() -> None:
    canvas, draw = pc_base(1, "书架  /  大屏浏览", "好故事", "在大屏舒展", "有声与阅读，集中在自己的书架。", "#FBF7F5")
    draw = app_window(canvas, "书架")
    draw.text((994, 332), "书架", fill=INK, font=font(44, True))
    draw.text((998, 394), "全部 4     有声书 3     电子书 1", fill=ROSE, font=font(20))
    covers = [
        ((998, 461, 1166, 681), (55, 535, 420, 1015), "夜无疆", "继续阅读"),
        ((1195, 461, 1363, 681), (461, 535, 826, 1015), "志怪书悬疑", "继续收听"),
        ((1392, 461, 1560, 681), (863, 535, 1228, 1015), "我叫赵甲", "继续收听"),
        ((1589, 461, 1757, 681), (55, 1235, 420, 1715), "蛊真人", "继续收听"),
    ]
    for box, crop, name, action in covers:
        book_cover(canvas, box, crop)
        draw.text((box[0], 702), name, fill=INK, font=font(20, True))
        draw.text((box[0], 741), action, fill=MUTED, font=font(17))
    draw.rounded_rectangle((996, 818, 1762, 866), radius=16, fill="#F4F4F4")
    draw.text((1021, 827), "最近阅读     夜无疆                         进度已保存", fill="#5F6061", font=font(18))
    save_pc(canvas, "01-library.png")

    canvas, draw = pc_base(2, "收听  /  继续播放", "听书进度", "始终跟得上", "章节、倍速与续播，按自己的节奏听。", "#F7F8F7")
    draw = app_window(canvas, "书架")
    draw.text((994, 326), "正在播放", fill=INK, font=font(40, True))
    book_cover(canvas, (995, 414, 1237, 738), (863, 535, 1228, 1015))
    draw.text((1284, 419), "我叫赵甲", fill=INK, font=font(40, True))
    draw.text((1287, 484), "第 516 集", fill=MUTED, font=font(24))
    draw.rounded_rectangle((1284, 574, 1719, 582), radius=4, fill="#E2E3E3")
    draw.rounded_rectangle((1284, 574, 1462, 582), radius=4, fill=ROSE)
    draw.text((1284, 594), "12:48", fill=MUTED, font=font(18))
    draw.text((1652, 594), "38:16", fill=MUTED, font=font(18))
    draw.ellipse((1401, 667, 1481, 747), fill=ROSE)
    draw.polygon(((1432, 687), (1432, 728), (1461, 707)), fill="#FFFFFF")
    draw.text((1305, 687), "上一集", fill="#555659", font=font(24))
    draw.text((1559, 687), "下一集", fill="#555659", font=font(24))
    draw.text((1285, 812), "倍速 1.0×        定时关闭        章节目录", fill=MUTED, font=font(20))
    save_pc(canvas, "02-listening.png")

    canvas, draw = pc_base(3, "阅读  /  专注此刻", "把阅读页", "调成喜欢的样子", "字号、行距、主题与位置，陪你继续读。", "#F6F7F4")
    draw = app_window(canvas, "", False)
    draw.text((814, 330), "夜无疆", fill=INK, font=font(23, True))
    draw.text((1500, 331), "第 478 章", fill=MUTED, font=font(20))
    draw.line((815, 390, 1747, 390), fill="#DED9D2", width=2)
    paragraphs = [
        "给自己留一点安静。",
        "把没读完的故事，接着读下去。",
        "熟悉的文字在眼前展开，阅读的位置仍然记得。",
        "停下时留住这一页，下次再从这里开始。",
    ]
    for index, paragraph in enumerate(paragraphs):
        draw.text((824, 430 + index * 82), paragraph, fill="#323431", font=font(28))
    draw.line((815, 797, 1747, 797), fill="#DED9D2", width=2)
    draw.text((824, 827), "羊皮纸      护眼绿      夜间      自定义", fill=MUTED, font=font(20))
    draw.text((1649, 827), "48%", fill=MUTED, font=font(20))
    save_pc(canvas, "03-reading.png")


if __name__ == "__main__":
    make_watch()
    make_pc()
