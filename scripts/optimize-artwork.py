"""Remove edge-connected medal backgrounds and losslessly optimize shipped PNGs.

Requires Pillow and numpy. Keeps pixel dimensions and icon RGBA pixel values.
"""
from collections import deque
from io import BytesIO
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / 'entry/src/main/resources/base/media'


def transparent_medal(image):
    if 'A' in image.getbands():
        return image.convert('RGBA')
    rgb = np.array(image.convert('RGB'))
    low = rgb.min(axis=2).astype(np.int16)
    high = rgb.max(axis=2).astype(np.int16)
    # Only the neutral light area connected to the canvas edge is background.
    # Enclosed white highlights, lettering and metallic reflections stay intact.
    candidate = (low >= 180) & (high - low <= 38)
    height, width = candidate.shape
    outside = np.zeros((height, width), dtype=bool)
    queue = deque()
    for y, x in [(y, x) for y in (0, height - 1) for x in range(width)] + [
            (y, x) for x in (0, width - 1) for y in range(height)]:
        if candidate[y, x] and not outside[y, x]:
            outside[y, x] = True
            queue.append((y, x))
    while queue:
        y, x = queue.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < height and 0 <= nx < width and candidate[ny, nx] and not outside[ny, nx]:
                outside[ny, nx] = True
                queue.append((ny, nx))
    # Rebuild a subpixel edge without retaining the baked white fringe.
    mask = Image.fromarray((~outside).astype(np.uint8) * 255)
    alpha = np.array(mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.55)))
    alpha[outside] = 0
    rgb[alpha == 0] = 0
    result = Image.fromarray(rgb).convert('RGBA')
    result.putalpha(Image.fromarray(alpha))
    return result


def main():
    before = after = 0
    for file in sorted(MEDIA.glob('reading_medal_*.webp')):
        original = file.stat().st_size
        image = transparent_medal(Image.open(file))
        image.save(file, lossless=True, method=6, exact=True)
        before += original
        after += file.stat().st_size
        print(f'{file.name}: {original} -> {file.stat().st_size}')
    print(f'Medals total: {before} -> {after}')
    before = after = 0
    for folder in (ROOT / 'AppScope/resources/base/media', MEDIA):
        for file in sorted(folder.glob('app_icon*.png')):
            original = file.stat().st_size
            image = Image.open(file)
            rgba = image.convert('RGBA').tobytes()
            if image.mode == 'RGBA' and image.getextrema()[3] == (255, 255):
                image = image.convert('RGB')
            output = BytesIO()
            image.save(output, format='PNG', optimize=True, compress_level=9)
            assert Image.open(BytesIO(output.getvalue())).convert('RGBA').tobytes() == rgba
            if len(output.getvalue()) < original:
                file.write_bytes(output.getvalue())
            before += original
            after += file.stat().st_size
    print(f'Icons total (both resource scopes): {before} -> {after}')


if __name__ == '__main__':
    main()
