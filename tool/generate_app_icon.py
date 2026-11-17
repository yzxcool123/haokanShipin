#!/usr/bin/env python3
"""Generate the 蓝果短剧 app icon masters.

Visual language is inspired by well-known short-drama app icons
(soft rounded play-triangle mark on a juicy fruit-colored gradient),
but the geometry and palette are original: blueberry / ice-aqua.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageChops

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "icon"
SIZE = 1024
SCALE = 4
HI = SIZE * SCALE


def mix(c1, c2, t: float):
    t = max(0.0, min(1.0, t))
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def gradient_background(size: int) -> Image.Image:
    """Diagonal juicy gradient: deep blueberry (BL) to ice aqua (TR)."""
    src = 160
    base = Image.new("RGB", (src, src))
    px = base.load()
    c_bl = (8, 72, 255)      # #0848FF
    c_mid = (58, 160, 255)   # #3AA0FF
    c_tr = (146, 238, 214)   # #92EED6
    for y in range(src):
        for x in range(src):
            # 红果-like diagonal: bottom-left warm/darker, top-right cooler/lighter
            t = (x * 0.72 + (src - 1 - y) * 1.0) / (src * 1.72)
            t = t**0.92
            if t < 0.55:
                col = mix(c_bl, c_mid, t / 0.55)
            else:
                col = mix(c_mid, c_tr, (t - 0.55) / 0.45)
            px[x, y] = col
    img = base.resize((size, size), Image.Resampling.LANCZOS)

    # Soft bloom near the upper-right so it feels more fruit-like, not flat.
    bloom = Image.new("RGB", (size, size), (0, 0, 0))
    bpx = bloom.load()
    accent = (190, 250, 235)
    cx, cy = size * 0.72, size * 0.22
    radius = size * 0.70
    for y in range(size):
        yy = (y - cy) / radius
        for x in range(size):
            xx = (x - cx) / radius
            d = math.sqrt(xx * xx + yy * yy)
            w = math.exp(-d * d * 2.4) * 0.38
            if w < 0.01:
                continue
            bpx[x, y] = tuple(int(c * w) for c in accent)
    inv_a = ImageChops.invert(img)
    inv_b = ImageChops.invert(bloom)
    return ImageChops.invert(ImageChops.multiply(inv_a, inv_b))


def capsule_triangle(size: int, pts, radius: int) -> Image.Image:
    """Filled triangle with circular corners and straight outer tangents."""
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    for x, y in pts:
        d.ellipse((x - radius, y - radius, x + radius, y + radius), fill=255)
    d.line(list(pts) + [pts[0]], fill=255, width=radius * 2, joint="curve")
    d.polygon(list(pts), fill=255)
    return m


def play_mark(size: int) -> Image.Image:
    """White rounded play-triangle ring with a play-shaped window."""
    s = size
    # Geometry is original (not a trace): a right-pointing soft play pebble.
    # Coordinates in the high-res canvas.
    cx, cy = s * 0.49, s * 0.50
    # Distance from center to vertex centers (before corner radius).
    # Slightly wider than tall so it reads as a play control.
    span_x = s * 0.22
    span_y = s * 0.205
    # Vertices of the inner skeleton (corner circle centers).
    left = cx - span_x * 0.72
    tip_x = cx + span_x * 0.95
    pts_outer = [
        (left, cy - span_y),   # top-left
        (left, cy + span_y),   # bottom-left
        (tip_x, cy),           # right tip
    ]
    r_outer = int(s * 0.152)

    # Inner play window: smaller, same orientation, optically shifted
    # a touch toward the tip so the white rim is thicker at the point.
    scale = 0.46
    ox, oy = s * 0.018, 0  # slight right shift
    pts_inner = [
        (cx + (x - cx) * scale + ox, cy + (y - cy) * scale + oy)
        for x, y in pts_outer
    ]
    r_inner = int(s * 0.086)

    outer = capsule_triangle(s, pts_outer, r_outer)
    inner = capsule_triangle(s, pts_inner, r_inner)
    ring = ImageChops.subtract(outer, inner)
    # Light AA
    ring = ring.filter(ImageFilter.GaussianBlur(radius=SCALE * 0.55))
    return ring


def compose_icon() -> tuple[Image.Image, Image.Image, Image.Image]:
    bg = gradient_background(SIZE)
    mark = play_mark(HI).resize((SIZE, SIZE), Image.Resampling.LANCZOS)

    icon = bg.convert("RGBA")
    white = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 255))
    icon = Image.composite(white, icon, mark)
    master = icon.convert("RGB")

    adaptive_bg = gradient_background(SIZE)

    # Foreground: just the mark, slightly inset for Android's safe zone.
    fg_hi = play_mark(HI)
    fg = Image.new("RGBA", (HI, HI), (0, 0, 0, 0))
    layer = Image.new("RGBA", (HI, HI), (255, 255, 255, 255))
    layer.putalpha(fg_hi)
    fg = Image.alpha_composite(fg, layer)
    box = int(HI * 0.04)
    inner = fg.crop((box, box, HI - box, HI - box)).resize((HI, HI), Image.Resampling.LANCZOS)
    foreground = inner.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    return master, adaptive_bg, foreground


def squircle_preview(icon: Image.Image, size: int = 512) -> Image.Image:
    src = icon.resize((size, size), Image.Resampling.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    r = int(size * 0.225)
    d.rounded_rectangle((0, 0, size - 1, size - 1), radius=r, fill=255)
    out = Image.new("RGBA", (size + 40, size + 40), (16, 17, 20, 255))
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
    squircle_preview(master).save(OUT / "app_icon_preview.png", "PNG")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
