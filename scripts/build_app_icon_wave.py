"""生成「声波」主题图标（app_icon_wave_*），新增到现有主题图标列表，不改动默认图标。

用法：python scripts/build_app_icon_wave.py
依赖 Pillow + numpy。渲染分两条路：
  · 前景层 —— 用本机 Chrome 无头截图 docs/icon-design/app_icon_foreground.svg
    （`--default-background-color=00000000` 输出带透明通道的 PNG，颜色无偏移）。
  · 背景层 —— 用 numpy 按 docs/icon-design/app_icon_background.svg 的同一组渐变参数
    逐像素算出。Chrome 渲染大面积渐变会引入 ±1 级抖动噪声，PNG 从 ~45 KB 涨到 508 KB，
    所以背景走程序化生成，保证画面纯净且体积可控。

产出（AppScope 与 entry 各一份，与 app_icon_leather 等主题图标同构）：
  app_icon_wave_background.png  满幅不透明背景
  app_icon_wave_foreground.png  透明底前景（含投影）
  app_icon_wave_legacy.png      合成图，供图标选择页预览与不支持分层图标的场景
  app_icon_wave.json            分层图标描述，供 app.json5 的 $media:app_icon_wave 引用
"""

import json
import os
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DESIGN = ROOT / 'docs/icon-design'
NAME = 'app_icon_wave'
SIZE = 1024
# 背景渐变参数，与 app_icon_background.svg 保持一致
LINEAR = ((0.06, 0.0), (0.62, 1.0),
          ((0.0, (62, 220, 169)), (0.44, (0, 168, 118)), (1.0, (0, 110, 76))))
GLOW = ((0.30, 0.12), 0.88, ((0.0, 0.26), (0.50, 0.05), (1.0, 0.0)))
VIGNETTE = ((0.5, 0.52), 0.78, (0.62, (0, 48, 31, 0.0)), (1.0, (0, 48, 31, 0.18)))
CHROME = os.environ.get('CHROME_PATH') or next(
    (p for p in (
        r'C:\Program Files\Google\Chrome\Application\chrome.exe',
        r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
        '/usr/bin/google-chrome',
        '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    ) if Path(p).exists()),
    None,
)
MEDIA_DIRS = (
    ROOT / 'AppScope/resources/base/media',
    ROOT / 'entry/src/main/resources/base/media',
)


def _ramp(t, stops):
    """按 SVG 渐变 stop 列表做线性插值，t 为 0..1 的归一化距离。"""
    stops = tuple((offset, (value,) if np.isscalar(value) else tuple(value))
                  for offset, value in stops)
    t = np.clip(t, 0.0, 1.0)[..., None]
    out = np.zeros(t.shape[:-1] + (len(stops[0][1]),))
    for (o1, c1), (o2, c2) in zip(stops, stops[1:]):
        span = np.clip((t - o1) / (o2 - o1), 0.0, 1.0)
        c1 = np.asarray(c1, dtype=np.float64)
        c2 = np.asarray(c2, dtype=np.float64)
        out = np.where((t >= o1) & (t <= o2), c1 + (c2 - c1) * span, out)
    out = np.where(t < stops[0][0], np.asarray(stops[0][1], dtype=np.float64), out)
    out = np.where(t > stops[-1][0], np.asarray(stops[-1][1], dtype=np.float64), out)
    return out


def _radial(x, y, center, radius):
    cx, cy = center[0] * SIZE, center[1] * SIZE
    return np.hypot(x - cx, y - cy) / (radius * SIZE)


def make_background():
    y, x = np.mgrid[0:SIZE, 0:SIZE].astype(np.float64)
    (x1, y1), (x2, y2) = LINEAR[0], LINEAR[1]
    vx, vy = (x2 - x1) * SIZE, (y2 - y1) * SIZE
    t = ((x - x1 * SIZE) * vx + (y - y1 * SIZE) * vy) / (vx * vx + vy * vy)
    base = _ramp(t, LINEAR[2])

    glow = _ramp(_radial(x, y, *GLOW[:2]), GLOW[2])
    base = np.asarray([255.0, 255.0, 255.0]) * glow + base * (1 - glow)

    vignette = _ramp(_radial(x, y, *VIGNETTE[:2]), (VIGNETTE[2], VIGNETTE[3]))
    color = np.asarray(VIGNETTE[2][1][:3], dtype=np.float64)
    alpha = vignette[..., 3:4]
    base = color * alpha + base * (1 - alpha)

    return Image.fromarray(np.clip(base + 0.5, 0, 255).astype(np.uint8), 'RGB')


def render_foreground():
    if CHROME is None:
        sys.exit('找不到 Chrome，可用 CHROME_PATH 环境变量指定可执行文件')
    out = DESIGN / 'build/foreground.png'
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars',
         '--force-device-scale-factor=1', f'--window-size={SIZE},{SIZE}',
         '--default-background-color=00000000', f'--screenshot={out}',
         (DESIGN / 'app_icon_foreground.svg').resolve().as_uri()],
        check=True, capture_output=True,
    )
    image = Image.open(out).convert('RGBA')
    if image.size != (SIZE, SIZE):
        raise ValueError(f'前景层渲染尺寸异常：{image.size}')
    return image


def flatten(image, colors=256, dither=Image.Dither.NONE, tolerance=4):
    """量化成调色板 PNG 压体积。渐变稿逐通道只差几级，肉眼不可见，
    但 PNG 体积能降到 1/4 左右。偏差超过 tolerance 直接报错。"""
    quantized = image.convert('RGB').quantize(
        colors=colors, method=Image.Quantize.MEDIANCUT, dither=dither)
    source = np.asarray(image.convert('RGB'), dtype=np.int16)
    delta = np.abs(source - np.asarray(quantized.convert('RGB'), dtype=np.int16))
    if delta.mean() > 1.5 or delta.max() > tolerance:
        raise ValueError(f'量化偏差过大：max={delta.max()} mean={delta.mean():.2f}')
    return quantized


def main():
    background = make_background()
    foreground = render_foreground()
    if foreground.getchannel('A').getextrema()[0] != 0:
        sys.exit('前景层缺少透明区域')
    box = foreground.getbbox()
    print(f'前景有效范围 {box}，占画布 '
          f'{(box[2] - box[0]) / SIZE:.0%} × {(box[3] - box[1]) / SIZE:.0%}')

    legacy = flatten(Image.alpha_composite(background.convert('RGBA'), foreground),
                     dither=Image.Dither.FLOYDSTEINBERG, tolerance=64)
    background = flatten(background)
    descriptor = {
        'layered-image': {
            'background': f'$media:{NAME}_background',
            'foreground': f'$media:{NAME}_foreground',
        }
    }
    for media_dir in MEDIA_DIRS:
        for suffix, image in (('background', background), ('foreground', foreground),
                              ('legacy', legacy)):
            path = media_dir / f'{NAME}_{suffix}.png'
            image.save(path, optimize=True)
            print(f'{path.relative_to(ROOT)}: {image.width}×{image.height} '
                  f'{path.stat().st_size / 1024:.1f} KB')
        json_path = media_dir / f'{NAME}.json'
        json_path.write_text(json.dumps(descriptor, indent=2) + '\n', encoding='utf-8')
        print(f'{json_path.relative_to(ROOT)}: 分层图标描述')


if __name__ == '__main__':
    main()
