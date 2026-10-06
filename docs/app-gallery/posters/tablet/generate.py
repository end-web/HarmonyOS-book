"""Render the 3:2 AppGallery promotional posters from project-owned assets."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[4]
OUTPUT = Path(__file__).resolve().parent
GALLERY = ROOT / "docs" / "app-gallery"
ARTICLE = ROOT / "docs" / "wechat-article" / "images"
SIZE = (1920, 1280)
FONT_REGULAR = "C:/Windows/Fonts/msyh.ttc"
FONT_BOLD = "C:/Windows/Fonts/msyhbd.ttc"
INK = "#202124"
MUTED = "#747579"
ACCENT = "#BC455C"


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_BOLD if bold else FONT_REGULAR, size)


def shadow(canvas: Image.Image, box: tuple[int, int, int, int], radius: int) -> None:
    layer = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle(box, radius=radius, fill=(39, 35, 34, 60))
    canvas.alpha_composite(layer.filter(ImageFilter.GaussianBlur(35)))


def rounded_image(canvas: Image.Image, source: Path, box: tuple[int, int, int, int], radius: int) -> None:
    left, top, right, bottom = box
    image = Image.open(source).convert("RGB")
    image = ImageOps.fit(image, (right - left, bottom - top), Image.Resampling.LANCZOS)
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, image.width, image.height), radius=radius, fill=255)
    canvas.paste(image, (left, top), mask)


def base(background: str, number: int, section: str) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    canvas = Image.new("RGBA", SIZE, background)
    draw = ImageDraw.Draw(canvas)
    icon = Image.open(GALLERY / "icon.png").convert("RGB").resize((64, 64), Image.Resampling.LANCZOS)
    canvas.paste(icon, (126, 63))
    draw.text((203, 72), "简听", fill=INK, font=font(35, True))
    draw.text((326, 82), "随心收听，静心阅读", fill=MUTED, font=font(22))
    draw.text((1630, 81), f"{number:02d} / 04", fill=ACCENT, font=font(26, True))
    draw.line((130, 153, 1790, 153), fill="#E7DFDE", width=2)
    draw.line((130, 1175, 1790, 1175), fill="#E7DFDE", width=2)
    draw.text((132, 1201), f"简听  /  {section}", fill=MUTED, font=font(24))
    draw.text((1667, 1201), "JIAN TING", fill=ACCENT, font=font(23, True))
    return canvas, draw


def title(draw: ImageDraw.ImageDraw, kicker: str, first: str, second: str, subtitle: str,
          y: int = 322, size: int = 106) -> None:
    draw.text((140, y - 87), kicker, fill=ACCENT, font=font(29, True))
    draw.text((132, y), first, fill=INK, font=font(size, True))
    draw.text((132, y + 139), second, fill=ACCENT, font=font(size, True))
    draw.text((141, y + 325), subtitle, fill=MUTED, font=font(31))


def phone(canvas: Image.Image, source: Path, background: str) -> None:
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((1135, 220, 1720, 1060), radius=68, fill=background)
    shadow(canvas, (1208, 180, 1668, 1130), 54)
    draw.rounded_rectangle((1203, 155, 1673, 1149), radius=62, fill="#25292B")
    rounded_image(canvas, source, (1223, 176, 1653, 1125), 43)
    draw.rounded_rectangle((1375, 180, 1501, 203), radius=11, fill="#25292B")


def tablet(canvas: Image.Image, source: Path, backdrop: str) -> None:
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((970, 235, 1755, 1036), radius=62, fill=backdrop)
    shadow(canvas, (918, 308, 1818, 980), 42)
    draw.rounded_rectangle((895, 279, 1820, 996), radius=49, fill="#25292B")
    rounded_image(canvas, source, (922, 302, 1793, 973), 25)
    draw.ellipse((903, 631, 912, 640), fill="#5D6265")


def save(canvas: Image.Image, name: str) -> None:
    canvas.convert("RGB").save(OUTPUT / name, "PNG", optimize=True)


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)

    canvas, draw = base("#FBF7F5", 1, "发现好故事")
    title(draw, "书架  /  有声与阅读", "好故事", "总有新发现", "把喜欢的内容，收进自己的书架。")
    phone(canvas, GALLERY / "screenshots" / "02-library.png", "#F2E6E5")
    save(canvas, "01-discover.png")

    canvas, draw = base("#F8F7F5", 2, "本地内容")
    title(draw, "导入  /  自己的内容", "本地好内容", "轻松收进来", "音频和电子书，随时加入书架。", size=97)
    phone(canvas, GALLERY / "screenshots" / "03-import.png", "#E9ECEB")
    save(canvas, "02-import.png")

    canvas, draw = base("#F9F6F5", 3, "自在收听")
    title(draw, "收听  /  跟随你的节奏", "自在收听", "跟着节奏走", "倍速、定时与续播，听书更从容。", size=90)
    tablet(canvas, ARTICLE / "04-listening.png", "#EFE2E3")
    save(canvas, "03-listening.png")

    canvas, draw = base("#F6F7F4", 4, "静心阅读")
    title(draw, "阅读  /  每一页都舒适", "静心阅读", "调成喜欢的样子", "字体、行距与配色，都由你决定。", size=86)
    tablet(canvas, ARTICLE / "05-reading.png", "#E7EDE6")
    save(canvas, "04-reading.png")


if __name__ == "__main__":
    main()
