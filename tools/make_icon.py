#!/usr/bin/env python3
"""Generates the Cairn app icon (a cairn: stacked stones, the top one
in brand red) for Android (legacy + adaptive) and Windows.

Run from the repo root:  python3 tools/make_icon.py
Design tokens come from DESIGN.md: charcoal #312D2A background, warm
stone tones, brand red #C74634 only on the top stone.
"""
from PIL import Image, ImageDraw

BG = (0x31, 0x2D, 0x2A, 255)
STONES = [
    # (width, height, center-y, color) as fractions of the canvas
    (0.56, 0.20, 0.665, (0xE9, 0xE7, 0xE4, 255)),
    (0.44, 0.18, 0.505, (0xCF, 0xC9, 0xC2, 255)),
    (0.32, 0.16, 0.360, (0xA8, 0x9F, 0x96, 255)),
    (0.20, 0.13, 0.238, (0xC7, 0x46, 0x34, 255)),  # top stone: brand red
]


def draw_stones(size: int) -> Image.Image:
    """The stones on a transparent square of `size` px."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = size / 2
    for w_f, h_f, cy_f, color in STONES:
        w, h, cy = w_f * size, h_f * size, cy_f * size
        d.rounded_rectangle(
            [cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2],
            radius=h / 2,
            fill=color,
        )
    return img


def full_icon(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), BG)
    img.alpha_composite(draw_stones(size))
    return img.convert("RGB")


def adaptive_foreground(size: int) -> Image.Image:
    """Stones inside the adaptive-icon safe zone (~66% center)."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    stones = draw_stones(size).resize(
        (int(size * 0.72), int(size * 0.72)), Image.LANCZOS
    )
    off = (size - stones.width) // 2
    img.alpha_composite(stones, (off, off))
    return img


def main() -> None:
    res = "apps/cairn_app/android/app/src/main/res"
    legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    foreground = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
    base = full_icon(1024)
    for density, px in legacy.items():
        base.resize((px, px), Image.LANCZOS).save(
            f"{res}/mipmap-{density}/ic_launcher.png"
        )
    fg_base = adaptive_foreground(1024)
    for density, px in foreground.items():
        fg_base.resize((px, px), Image.LANCZOS).save(
            f"{res}/mipmap-{density}/ic_launcher_foreground.png"
        )
    base.save(
        "apps/cairn_app/windows/runner/resources/app_icon.ico",
        sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)],
    )
    print("icons written")


if __name__ == "__main__":
    main()
