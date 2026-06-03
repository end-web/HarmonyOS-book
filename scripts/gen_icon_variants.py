"""
三套图标方案。所有套件:
  - 1024x1024 背景图
  - 1024x1024 前景图（音波/书本分色 + 立体悬浮）
  - 1024x1024 合成预览
输出到 docs/icon-variants/{A,B,C}/
"""

import os
import subprocess
import numpy as np
from collections import deque
from PIL import Image, ImageFilter, ImageChops

ROOT = "d:/ListenBook"
OUT = os.path.join(ROOT, "docs/icon-variants")
os.makedirs(OUT, exist_ok=True)

# ------------------------------------------------------------------
# 0) 取一次原始前景，做连通分量分类（音波 / 书本）
# ------------------------------------------------------------------
raw = "/tmp/fg_orig_v3.png"
subprocess.run(
    ["git", "show", "HEAD:AppScope/resources/base/media/app_icon_foreground.png"],
    cwd=ROOT,
    stdout=open(raw, "wb"),
    check=True,
)
orig = Image.open(raw).convert("RGBA")
W, H = orig.size
arr_a = np.array(orig.split()[-1])
solid = arr_a == 255

labels = np.zeros(solid.shape, dtype=np.int32)
nxt = 0
for i in range(H):
    for j in range(W):
        if solid[i, j] and labels[i, j] == 0:
            nxt += 1
            q = deque([(i, j)])
            labels[i, j] = nxt
            while q:
                y, x = q.popleft()
                for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < H and 0 <= nx < W and solid[ny, nx] and labels[ny, nx] == 0:
                        labels[ny, nx] = nxt
                        q.append((ny, nx))

audio_labels = []
book_labels = []
for k in range(1, nxt + 1):
    ys, xs = np.where(labels == k)
    if len(ys) < 5:
        continue
    bh = ys.max() - ys.min() + 1
    bw = xs.max() - xs.min() + 1
    if bw <= 30 and bh / bw >= 1.5:
        audio_labels.append(k)
    else:
        book_labels.append(k)

audio_mask_arr = np.isin(labels, audio_labels).astype(np.uint8) * 255
book_mask_arr = np.isin(labels, book_labels).astype(np.uint8) * 255


def smooth(mask_arr):
    m = Image.fromarray(mask_arr, "L")
    m = m.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))
    m = m.filter(ImageFilter.GaussianBlur(radius=0.6))
    return m


audio_mask = smooth(audio_mask_arr)
book_mask = smooth(book_mask_arr)
full_mask = ImageChops.lighter(audio_mask, book_mask)


def color_layer(mask, rgb, opacity=255):
    fill = Image.new("RGBA", (W, H), (rgb[0], rgb[1], rgb[2], opacity))
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.paste(fill, (0, 0), mask)
    return out


def shadow_layer(mask, color_alpha, blur_px, off_x, off_y, color=(0, 0, 0)):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    fill = Image.new("RGBA", (W, H), (color[0], color[1], color[2], color_alpha))
    layer.paste(fill, (0, 0), mask)
    layer = layer.filter(ImageFilter.GaussianBlur(radius=blur_px))
    if off_x or off_y:
        layer = ImageChops.offset(layer, off_x, off_y)
    return layer


def stack(layers):
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for L in layers:
        out = Image.alpha_composite(out, L)
    return out


def vertical_gradient(c_top, c_bot):
    t = np.linspace(0, 1, H, dtype=np.float32).reshape(H, 1, 1)
    grad = np.array(c_top, np.float32) * (1 - t) + np.array(c_bot, np.float32) * t
    return np.broadcast_to(grad, (H, W, 3)).astype(np.uint8)


def diag_gradient(c_tl, c_br):
    ys, xs = np.indices((H, W), dtype=np.float32)
    t = np.clip((xs + ys) / (W + H - 2), 0, 1)[:, :, None]
    grad = np.array(c_tl, np.float32) * (1 - t) + np.array(c_br, np.float32) * t
    return grad.astype(np.uint8)


def radial_glow(base_arr, cx, cy, radius_px, color, strength):
    ys, xs = np.indices((H, W), dtype=np.float32)
    d2 = (xs - cx) ** 2 + (ys - cy) ** 2
    sigma2 = (radius_px ** 2) / 2.0
    falloff = np.exp(-d2 / sigma2)[:, :, None]
    alpha = falloff * strength
    return (
        base_arr.astype(np.float32) * (1 - alpha) + np.array(color, np.float32) * alpha
    ).clip(0, 255).astype(np.uint8)


def top_highlight(mask, peak_alpha, top_pct, color=(255, 255, 255)):
    grad = np.zeros((H, W), dtype=np.uint8)
    top_h = int(H * top_pct)
    for y in range(top_h):
        grad[y, :] = int(peak_alpha * (1 - y / top_h))
    grad_img = Image.fromarray(grad, "L")
    a = ImageChops.multiply(grad_img, mask)
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    layer.paste(
        Image.new("RGBA", (W, H), (color[0], color[1], color[2], peak_alpha)),
        (0, 0),
        a,
    )
    return layer


def bottom_rim(mask, peak_alpha, bot_pct, color):
    grad = np.zeros((H, W), dtype=np.uint8)
    rim_h = int(H * bot_pct)
    for y in range(rim_h):
        grad[H - 1 - y, :] = int(peak_alpha * (1 - y / rim_h))
    grad_img = Image.fromarray(grad, "L")
    a = ImageChops.multiply(grad_img, mask)
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    layer.paste(
        Image.new("RGBA", (W, H), (color[0], color[1], color[2], peak_alpha)),
        (0, 0),
        a,
    )
    return layer


def outer_glow(mask, color, alpha, blur_px):
    base = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    base.paste(
        Image.new("RGBA", (W, H), (color[0], color[1], color[2], alpha)),
        (0, 0),
        mask,
    )
    base = base.filter(ImageFilter.GaussianBlur(radius=blur_px))
    return base


def save_set(out_dir, bg, fg):
    bg.save(os.path.join(out_dir, "app_icon_background.png"), "PNG", optimize=True)
    fg.save(os.path.join(out_dir, "app_icon_foreground.png"), "PNG", optimize=True)
    composite = Image.alpha_composite(bg.convert("RGBA"), fg)
    composite.convert("RGB").save(
        os.path.join(out_dir, "preview.png"), "PNG", optimize=True
    )


# ------------------------------------------------------------------
# 方案 A：奶白沙系（Apple Books 气质，扁平精致）
# ------------------------------------------------------------------
def variant_A():
    out_dir = os.path.join(OUT, "A")
    os.makedirs(out_dir, exist_ok=True)
    bg_arr = diag_gradient((0xFF, 0xF1, 0xE0), (0xFF, 0xD9, 0xB0))
    bg_arr = radial_glow(bg_arr, W * 0.22, H * 0.18, W * 0.85, (255, 250, 235), 0.30)
    bg = Image.fromarray(bg_arr, "RGB")

    BOOK_C = (0x1F, 0x3D, 0x2B)
    AUDIO_C = (0xE8, 0xA2, 0x3A)

    book_l = color_layer(book_mask, BOOK_C)
    audio_l = color_layer(audio_mask, AUDIO_C)
    body = Image.alpha_composite(book_l, audio_l)

    sh_far = shadow_layer(full_mask, 70, 40, 0, 30, color=(80, 40, 10))
    sh_near = shadow_layer(full_mask, 110, 10, 0, 8, color=(80, 40, 10))
    hl = top_highlight(full_mask, 60, 0.45)

    fg = stack([sh_far, sh_near, body, hl])
    save_set(out_dir, bg, fg)


# ------------------------------------------------------------------
# 方案 B：深夜电台（深色高级、霓虹音波）
# ------------------------------------------------------------------
def variant_B():
    out_dir = os.path.join(OUT, "B")
    os.makedirs(out_dir, exist_ok=True)
    bg_arr = vertical_gradient((0x1A, 0x0B, 0x45), (0x0B, 0x04, 0x20))
    bg_arr = radial_glow(bg_arr, W * 0.5, H * 0.0, W * 0.7, (130, 90, 220), 0.25)
    bg = Image.fromarray(bg_arr, "RGB")

    BOOK_C = (0xF5, 0xEB, 0xD8)
    AUDIO_C = (0xFF, 0xC8, 0x3D)

    book_l = color_layer(book_mask, BOOK_C)
    audio_l = color_layer(audio_mask, AUDIO_C)
    body = Image.alpha_composite(book_l, audio_l)

    audio_glow = outer_glow(audio_mask, AUDIO_C, 180, 24)
    audio_glow2 = outer_glow(audio_mask, (255, 200, 80), 120, 55)

    sh_far = shadow_layer(full_mask, 160, 55, 0, 45, color=(0, 0, 0))
    sh_near = shadow_layer(full_mask, 180, 12, 0, 10, color=(0, 0, 0))
    sh_ao = shadow_layer(full_mask, 140, 4, 0, 0, color=(0, 0, 0))
    hl = top_highlight(full_mask, 55, 0.45)

    fg = stack([sh_far, audio_glow2, audio_glow, sh_near, sh_ao, body, hl])
    save_set(out_dir, bg, fg)


# ------------------------------------------------------------------
# 方案 C：朱红玉脂（红色基调 + 米白书本 + 亮黄音波平衡）
# ------------------------------------------------------------------
def variant_C():
    out_dir = os.path.join(OUT, "C")
    os.makedirs(out_dir, exist_ok=True)
    bg_arr = vertical_gradient((0xFF, 0x4A, 0x56), (0xC7, 0x14, 0x2D))
    bg_arr = radial_glow(bg_arr, W * 0.5, H * 0.0, W * 0.8, (255, 200, 180), 0.20)
    bg = Image.fromarray(bg_arr, "RGB")

    BOOK_C = (0xFF, 0xF1, 0xDD)
    AUDIO_C = (0xFF, 0xD2, 0x3F)

    book_l = color_layer(book_mask, BOOK_C)
    audio_l = color_layer(audio_mask, AUDIO_C)
    body = Image.alpha_composite(book_l, audio_l)

    sh_far = shadow_layer(full_mask, 120, 55, 0, 50, color=(120, 10, 20))
    sh_near = shadow_layer(full_mask, 170, 14, 0, 12, color=(80, 5, 15))
    sh_ao = shadow_layer(full_mask, 140, 4, 0, 0, color=(80, 5, 15))
    hl = top_highlight(full_mask, 85, 0.5)
    rim = bottom_rim(full_mask, 70, 0.3, (0xC7, 0x14, 0x2D))

    fg = stack([sh_far, sh_near, sh_ao, body, hl, rim])
    save_set(out_dir, bg, fg)


variant_A()
variant_B()
variant_C()

print("done")
for v in ("A", "B", "C"):
    p = os.path.join(OUT, v)
    print(v, sorted(os.listdir(p)))
