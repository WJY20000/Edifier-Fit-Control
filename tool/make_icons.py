#!/usr/bin/env python3
"""生成应用图标（纯 Pillow，不依赖任何外部素材）。

用法：
    python3 tool/make_icons.py

输出：
    assets/branding/icon_1024.png
    assets/branding/icon_512.png
    assets/branding/app_icon.ico
    tool/icons/ic_launcher_{48,72,96,144,192}.png

图标设计：漫步者蓝渐变圆角底 + 白色耳机轮廓（蓝色取自 2026 新版品牌色 #0088C9）。
"""

from __future__ import annotations

import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ACCENT = (0, 136, 201)      # #0088C9，新版漫步者图标的主色
ACCENT_DARK = (0, 90, 133)  # #005A85
ACCENT_LIGHT = (69, 182, 238)  # #45B6EE
INK = (18, 20, 26)


def lerp(a: int, b: int, t: float) -> int:
    return int(round(a + (b - a) * t))


def vertical_gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    image = Image.new("RGB", (1, size))
    pixels = image.load()
    for y in range(size):
        t = y / max(1, size - 1)
        pixels[0, y] = (
            lerp(top[0], bottom[0], t),
            lerp(top[1], bottom[1], t),
            lerp(top[2], bottom[2], t),
        )
    return image.resize((size, size), Image.Resampling.BILINEAR)


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def draw_headphones(draw: ImageDraw.ImageDraw, size: int, color=(255, 255, 255, 255)) -> None:
    s = size / 1024.0
    # 头梁：上半圆环
    band_box = (int(210 * s), int(232 * s), int(814 * s), int(836 * s))
    draw.arc(band_box, start=182, end=358, fill=color, width=int(62 * s))
    # 左右耳罩
    for x0 in (196, 636):
        box = (int(x0 * s), int(540 * s), int((x0 + 192) * s), int(812 * s))
        draw.rounded_rectangle(box, radius=int(74 * s), fill=color)
    # 耳罩内的品牌色细节
    for x0 in (196, 636):
        box = (int((x0 + 52) * s), int(614 * s), int((x0 + 140) * s), int(742 * s))
        draw.rounded_rectangle(box, radius=int(40 * s), fill=ACCENT)


def render(size: int) -> Image.Image:
    base = vertical_gradient(size, ACCENT_LIGHT, ACCENT_DARK)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(base, (0, 0), rounded_mask(size, int(size * 0.235)))

    # 一层很淡的内描边，缩到 48px 时不至于糊成一团
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(
        (int(size * 0.012), int(size * 0.012), int(size * 0.988), int(size * 0.988)),
        radius=int(size * 0.225),
        outline=(255, 255, 255, 30),
        width=max(1, int(size * 0.006)),
    )
    draw_headphones(draw, size)
    return canvas


def main() -> None:
    branding = os.path.join(ROOT, "assets", "branding")
    icons = os.path.join(ROOT, "tool", "icons")
    os.makedirs(branding, exist_ok=True)
    os.makedirs(icons, exist_ok=True)

    big = render(1024)
    big.save(os.path.join(branding, "icon_1024.png"))
    render(512).save(os.path.join(branding, "icon_512.png"))
    render(256).save(os.path.join(branding, "icon_256.png"))

    # Windows .ico：多尺寸，16/24/32 用稍粗的图案也能看清
    ico_sizes = [16, 24, 32, 48, 64, 128, 256]
    frames = [render(size).convert("RGBA") for size in ico_sizes]
    frames[-1].save(
        os.path.join(branding, "app_icon.ico"),
        format="ICO",
        sizes=[(s, s) for s in ico_sizes],
        append_images=frames[:-1],
    )

    # Android 传统启动图标
    for size in (48, 72, 96, 144, 192):
        render(size).save(os.path.join(icons, f"ic_launcher_{size}.png"))

    print("icons written")


if __name__ == "__main__":
    main()
