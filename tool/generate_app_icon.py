#!/usr/bin/env python3
"""Generate the 好看视频 app icon masters."""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "icon"
SIZE = 1024
SCALE = 4
HI = SIZE * SCALE


def mix(c1, c2, t: float):
    t = max(0.0, min(1.0, t))
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def gradient_background(size: int) -> Image.Image:
    src = 96
    base = Image.new("RGB", (src, src))
    px = base.load()
    c0 = (8, 10, 20)    # #080A14
    c1 = (28, 46, 102)  # #1C2E66
    for y in range(src):
        for x in range(src):
            t = (x * 0.45 + y * 1.0) / (src * 1.45)
            px[x, y] = mix(c0, c1, t**0.85)
    img = base.resize((size, size), Image.Resampling.LANCZOS)

    glow = Image.new("RGB", (size, size), (0, 0, 0))
    gpx = glow.load()
    accent = (124, 156, 255)
    cx, cy = size * 0.58, size * 0.60
    radius = size * 0.62
    for y in range(size):
        yy = (y - cy) / radius
        for x in range(size):
            xx = (x - cx) / radius
            d = math.sqrt(xx * xx + yy * yy)
            w = math.exp(-d * d * 2.15)
            if w < 0.01:
                continue
            gpx[x, y] = tuple(int(c * w) for c in accent)
    return ImageChopsScreen(img, glow)


def ImageChopsScreen(a: Image.Image, b: Image.Image) -> Image.Image:
    # screen blend: 1 - (1-a)(1-b)
    from PIL import ImageChops

    inv_a = ImageChops.invert(a)
    inv_b = ImageChops.invert(b)
    return ImageChops.invert(ImageChops.multiply(inv_a, inv_b))


def _ellipse(draw: ImageDraw.ImageDraw, c, r, **kwargs):
    draw.ellipse((c - r, c - r, c + r, c + r), **kwargs)


def mark_layers(size: int):
    """Return (ring, play, play_highlight) as 'L' masks at `size`."""
    ring = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(ring)
    c = size // 2
    outer = int(size * 0.36)
    width = max(int(size * 0.028), 8)
    _ellipse(d, c, outer, fill=255)
    _ellipse(d, c, outer - width, fill=0)
    # soft AA
    ring = ring.filter(ImageFilter.GaussianBlur(radius=SCALE * 0.45))

    play = Image.new("L", (size, size), 0)
    pd = ImageDraw.Draw(play)
    # Optical center: shift right slightly so the triangle feels centered in the ring.
    cx, cy = size * 0.525, size * 0.50
    w, h = size * 0.205, size * 0.238
    pts = [
        (cx - w * 0.62, cy - h / 2),
        (cx - w * 0.62, cy + h / 2),
        (cx + w * 0.78, cy),
    ]
    pd.polygon(pts, fill=255)
    # Modest rounded corners, then light AA.
    corner = max(int(size * 0.0075), 8)
    pd.line(pts + [pts[0]], fill=255, width=corner * 2, joint="curve")
    play = play.filter(ImageFilter.GaussianBlur(radius=SCALE * 0.6))
    play = play.point(lambda v: 255 if v > 90 else 0)
    play = play.filter(ImageFilter.GaussianBlur(radius=SCALE * 0.45))

    # Top-left sheen on the triangle.
    sheen = Image.new("L", (size, size), 0)
    sd = ImageDraw.Draw(sheen)
    sd.ellipse(
        (
            cx - w * 1.15,
            cy - h * 1.15,
            cx + w * 0.15,
            cy + h * 0.10,
        ),
        fill=255,
    )
    sheen = sheen.filter(ImageFilter.GaussianBlur(radius=size * 0.06))
    sheen = ImageChops.multiply(sheen, play)
    return ring, play, sheen


def ImageChops():
    from PIL import ImageChops as m

    return m


# Fix late import usage in mark_layers
from PIL import ImageChops as ImageChopsMod
ImageChops = ImageChopsMod  # used by gradient and we'll patch mark_layers to use ImageChopsMod


def compose_icon() -> tuple[Image.Image, Image.Image, Image.Image]:
    bg = gradient_background(SIZE)

    ring, play, sheen = mark_layers(HI)
    ring = ring.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    play = play.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    sheen = sheen.resize((SIZE, SIZE), Image.Resampling.LANCZOS)

    # Soft colored halo behind the mark, on the background.
    halo = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    hd = ImageDraw.Draw(halo)
    c = SIZE // 2
    hd.ellipse((c - 340, c - 340, c + 340, c + 340), fill=(90, 120, 230))
    halo = halo.filter(ImageFilter.GaussianBlur(radius=90))
    bg = ImageChops.screen(bg, Image.blend(Image.new("RGB", (SIZE, SIZE), (0, 0, 0)), halo, 0.55))

    icon = bg.convert("RGBA")

    ring_color = Image.new("RGBA", (SIZE, SIZE), (236, 242, 255, 255))
    icon = Image.composite(ring_color, icon, ring)

    play_color = Image.new("RGBA", (SIZE, SIZE), (247, 250, 255, 255))
    icon = Image.composite(play_color, icon, play)

    sheen_color = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 255))
    # Subtle highlight only
    sheen_alpha = sheen.point(lambda v: int(v * 0.35))
    icon = Image.composite(sheen_color, icon, sheen_alpha)

    master = icon.convert("RGB")

    # Adaptive background: same gradient without the mark, slightly calmer.
    adaptive_bg = gradient_background(SIZE)

    # Adaptive foreground: mark on transparent, a bit smaller for safe zone.
    fg = Image.new("RGBA", (HI, HI), (0, 0, 0, 0))
    ring_h, play_h, sheen_h = mark_layers(HI)
    # Scale mark to 82% around center to leave Android safe zone.
    def paste_mask(base, mask, color, alpha_scale=1.0):
        layer = Image.new("RGBA", mask.size, color)
        a = mask if alpha_scale == 1.0 else mask.point(lambda v: int(v * alpha_scale))
        layer.putalpha(a)
        return Image.alpha_composite(base, layer)

    fg = paste_mask(fg, ring_h, (236, 242, 255, 255))
    fg = paste_mask(fg, play_h, (247, 250, 255, 255))
    fg = paste_mask(fg, sheen_h, (255, 255, 255, 255), 0.35)
    # shrink toward center
    box = int(HI * 0.09)
    inner = fg.crop((box, box, HI - box, HI - box)).resize((HI, HI), Image.Resampling.LANCZOS)
    foreground = inner.resize((SIZE, SIZE), Image.Resampling.LANCZOS)

    return master, adaptive_bg, foreground


def squircle_preview(icon: Image.Image, size: int = 512) -> Image.Image:
    """Home-screen style preview with a squircle mask, for showing the user."""
    src = icon.resize((size, size), Image.Resampling.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    r = int(size * 0.225)
    d.rounded_rectangle((0, 0, size - 1, size - 1), radius=r, fill=255)
    out = Image.new("RGBA", (size + 40, size + 40), (16, 17, 20, 255))
    # drop shadow
    shadow = Image.new("L", (size + 40, size + 40), 0)
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((24, 28, 24 + size - 1, 28 + size - 1), radius=r, fill=180)
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=10))
    sh_layer = Image.new("RGBA", out.size, (0, 0, 0, 0))
    sh_layer.putalpha(shadow)
    out = Image.alpha_composite(out, sh_layer)
    tile = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    tile.paste(src.convert("RGBA"))
    tile.putalpha(mask)
    out.paste(tile, (20, 20), tile)
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    master, background, foreground = compose_icon()
    master.save(OUT / "app_icon.png", "PNG")
    background.save(OUT / "app_icon_background.png", "PNG")
    foreground.save(OUT / "app_icon_foreground.png", "PNG")
    preview = squircle_preview(master)
    preview.save(OUT / "app_icon_preview.png", "PNG")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
