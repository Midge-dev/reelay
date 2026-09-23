#!/usr/bin/env python3
"""Renders Reelay's raster brand assets from design_handoff_reelay_brand.

Everything is drawn from the handoff's geometry and Nocturne tokens (the
Play listing and launcher ship Nocturne — "it's the brand"), so re-running
this reproduces the same files. The adaptive-icon layers are vector
drawables in android/app/src/main/res/drawable and aren't generated here.

    python3 tools/brand_assets.py

Writes:
  flutter/android/app/src/main/res/drawable-xhdpi/tv_banner.png   320×180
  flutter/android/app/src/main/res/mipmap-*/ic_launcher.png       legacy (pre-API 26)
  brand/play_icon_512.png                                         Play hi-res icon
  brand/feature_graphic_1024x500.png                              Play feature graphic
"""

import math
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "flutter/android/app/src/main/res")
FONT = os.path.join(ROOT, "flutter/assets/fonts/Inter-Variable.ttf")

# Nocturne (tokens.dart).
CANVAS = (0x12, 0x14, 0x1F)
BACKGROUND = (0x16, 0x18, 0x26)
SURFACE = (0x1D, 0x1F, 0x30)
ACCENT = (0x91, 0x84, 0xD9)
INK = (0xE9, 0xE9, 0xED)
INK2 = (0xC8, 0xCA, 0xD8)

SS = 4  # supersampling factor for smooth edges


def _lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def _stops(t, stops):
    t = max(0.0, min(1.0, t))
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        if t <= p1:
            return _lerp(c0, c1, (t - p0) / (p1 - p0) if p1 > p0 else 0)
    return stops[-1][1]


def icon_ground(w, h):
    """CSS linear-gradient(160deg, surface 0%, background 55%, canvas 100%)."""
    a = math.radians(160)
    dx, dy = math.sin(a), -math.cos(a)
    length = abs(w * dx) + abs(h * dy)
    stops = [(0, SURFACE), (0.55, BACKGROUND), (1, CANVAS)]
    img = Image.new("RGB", (w, h))
    px = img.load()
    cx, cy = w / 2, h / 2
    for y in range(h):
        for x in range(w):
            t = ((x + 0.5 - cx) * dx + (y + 0.5 - cy) * dy) / length + 0.5
            px[x, y] = _stops(t, stops)
    return img


def feature_ground(w, h):
    """CSS radial-gradient(90% 120% at 18% 50%, surface, background 50%, canvas)."""
    rx, ry = 0.9 * w, 1.2 * h
    cx, cy = 0.18 * w, 0.5 * h
    stops = [(0, SURFACE), (0.5, BACKGROUND), (1, CANVAS)]
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = math.hypot((x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry)
            px[x, y] = _stops(t, stops)
    return img


def draw_mark(layer, x, y, bar_w, bar_h, scale=SS, second=INK):
    """The mark in 36×28 units (bars 36×12 and 22×12, gap 4, r4) at bar_w wide."""
    u = bar_w / 36
    d = ImageDraw.Draw(layer)
    r = 4 * u * scale
    d.rounded_rectangle(
        [x * scale, y * scale, (x + 36 * u) * scale, (y + 12 * u) * scale],
        radius=r, fill=ACCENT + (255,))
    d.rounded_rectangle(
        [x * scale, (y + 16 * u) * scale, (x + 22 * u) * scale, (y + 28 * u) * scale],
        radius=r, fill=second + (255,))


def inter(size, design_px, weight=500):
    # Axes are [optical size 14–32, weight]. Browsers (the handoff) apply
    # optical sizing automatically — the font size, clamped — so match it.
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_axes([max(14, min(32, design_px)), weight])
    return f


def draw_text(layer, x, y_center, text, size_px, tracking_em, color, scale=SS, weight=500):
    """Inter with CSS letter-spacing, vertically centred on y_center."""
    f = inter(round(size_px * scale), size_px, weight)
    d = ImageDraw.Draw(layer)
    cursor = x * scale
    top, bottom = f.getbbox("R")[1], f.getbbox("R")[3]
    baseline_y = y_center * scale - (top + bottom) / 2
    for ch in text:
        d.text((cursor, baseline_y), ch, font=f, fill=color + (255,))
        cursor += f.getlength(ch) + tracking_em * size_px * scale
    return cursor / scale - x - tracking_em * size_px


def text_width(text, size_px, tracking_em):
    f = inter(size_px * 8, size_px)
    w = sum(f.getlength(c) for c in text) / 8
    return w + tracking_em * size_px * (len(text) - 1)


def compose(ground, overlay_fn):
    w, h = ground.size
    big = ground.resize((w * SS, h * SS), Image.NEAREST).convert("RGBA")
    layer = Image.new("RGBA", big.size, (0, 0, 0, 0))
    overlay_fn(layer)
    big.alpha_composite(layer)
    # Area-average down: LANCZOS rings into a dark halo at the bars' edges.
    return big.resize((w, h), Image.BOX).convert("RGB")


def lockup(layer, cx, cy, mark_w, mark_h, gap, font_px, color=INK):
    """Mark + wordmark, centred as one group on (cx, cy)."""
    tw = text_width("Reelay", font_px, -0.03)
    total = mark_w + gap + tw
    x0 = cx - total / 2
    draw_mark(layer, x0, cy - mark_h / 2, mark_w, mark_h)
    draw_text(layer, x0 + mark_w + gap, cy, "Reelay", font_px, -0.03, color)


def tv_banner():
    # Brand sheet: 640×360 shown at 2× — mark 120×94, gap 28, wordmark 104.
    w, h = 320, 180
    img = compose(icon_ground(w, h), lambda L: lockup(L, w / 2, h / 2, 60, 47, 14, 52))
    out = os.path.join(RES, "drawable-xhdpi", "tv_banner.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out)
    return out


def square_icon(size, rounded):
    # 100-unit grid: bars at x30, y34.44 (40×13.33) and y52.22 (24.44×13.33).
    s = size / 100
    def overlay(L):
        draw_mark(L, 30 * s, 34.44 * s, 40 * s, 31.11 * s)
    img = compose(icon_ground(size, size), overlay)
    if rounded:
        # Legacy launchers show the PNG as-is; round it like the sheet's
        # "as listed" preview (radius 21/96).
        mask = Image.new("L", (size * SS, size * SS), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [0, 0, size * SS - 1, size * SS - 1], radius=size * SS * 21 / 96, fill=255)
        mask = mask.resize((size, size), Image.BOX)
        rgba = img.convert("RGBA")
        rgba.putalpha(mask)
        return rgba
    return img


def legacy_launchers():
    outs = []
    for density, px in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
        out = os.path.join(RES, f"mipmap-{density}", "ic_launcher.png")
        square_icon(px, rounded=True).save(out)
        outs.append(out)
    return outs


def play_icon():
    out = os.path.join(ROOT, "brand", "play_icon_512.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    # Full-bleed, no alpha — Play applies the mask.
    square_icon(512, rounded=False).save(out)
    return out


def feature_graphic():
    w, h = 1024, 500
    tagline = "Plex and Jellyfin, one quiet place to watch."
    def overlay(L):
        # Column centred vertically: lockup (78 tall) + 34 gap + tagline (30 × 1.35).
        line_h = 30 * 1.35
        block = 78 + 34 + line_h
        top = (h - block) / 2
        draw_mark(L, 96, top, 100, 78)
        draw_text(L, 96 + 100 + 26, top + 39, "Reelay", 88, -0.03, INK)
        draw_text(L, 96, top + 78 + 34 + line_h / 2, tagline, 30, 0, INK2, weight=400)
    out = os.path.join(ROOT, "brand", "feature_graphic_1024x500.png")
    compose(feature_ground(w, h), overlay).save(out)
    return out


if __name__ == "__main__":
    for path in [tv_banner(), *legacy_launchers(), play_icon(), feature_graphic()]:
        print(os.path.relpath(path, ROOT))
