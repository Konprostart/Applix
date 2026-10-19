#!/usr/bin/env python3
"""Generate Applix icon PNGs from the brand mark (no external dependencies).

Usage:
  python3 tools/gen_icons.py            # writes docs/brand/*.png previews
  python3 tools/gen_icons.py --apply    # also updates Android mipmaps + assets

The vector source of truth is docs/brand/applix-logo.svg. If rsvg-convert or
cairosvg is available it is used for a higher-fidelity render; otherwise this
script falls back to its built-in renderer, which implements the same shapes
from the same geometry constants.

The built-in renderer comes in two flavours: a vectorised NumPy implementation
(used when NumPy is importable) and a pure-Python fallback. The pure-Python one
is exact but slow at 1024px - install NumPy (pip install numpy) for a fast run.
"""

import math
import os
import shutil
import struct
import subprocess
import sys
import zlib

try:
    import numpy as _np
except ImportError:  # optional - only used to speed up rasterisation
    _np = None

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SVG = os.path.join(ROOT, "docs", "brand", "applix-logo.svg")
RES = os.path.join(ROOT, "src", "container_app", "android", "app", "src", "main", "res")
ASSETS = os.path.join(ROOT, "src", "container_app", "assets")

BG_TOP = (27, 27, 58)
BG_MID = (43, 26, 85)
BG_BOT = (75, 31, 122)
GLYPH_TOP = (255, 255, 255)
GLYPH_BOT = (139, 233, 253)
ACCENT = (139, 233, 253)
ACCENT_INNER = (255, 255, 255)

# Outer "A" polygon and its counter (hole), in the 512x512 SVG coordinate space.
A_OUTER = [(256, 116), (372, 384), (310, 384), (290, 334),
           (222, 334), (202, 384), (140, 384)]
A_HOLE = [(256, 212), (234, 274), (278, 274)]


def _lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def _bg_color(x, y, size):
    """Diagonal gradient (SVG: x1=0,y1=0 -> x2=1,y2=1) in objectBoundingBox."""
    t = (x / size + y / size) / 2.0
    if t < 0.55:
        return _lerp(BG_TOP, BG_MID, t / 0.55)
    return _lerp(BG_MID, BG_BOT, (t - 0.55) / 0.45)


def _point_in_poly(x, y, poly):
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y):
            xint = (xj - xi) * (y - yi) / (yj - yi) + xi
            if x < xint:
                inside = not inside
        j = i
    return inside


def _in_rounded_rect(x, y, w, h, r):
    if x < 0 or y < 0 or x >= w or y >= h:
        return False
    cx = min(max(x, r), w - r)
    cy = min(max(y, r), h - r)
    dx, dy = x - cx, y - cy
    return dx * dx + dy * dy <= r * r


def _render_python(size, foreground=False, ss=4):
    """Return RGBA bytes for one icon at `size` px (pure Python, exact but slow)."""
    w = h = size
    scale = 512.0 / size
    radius = 112.0 * (size / 512.0)
    # Adaptive foreground keeps the glyph inside the 66dp safe zone of 108dp.
    glyph_scale = 0.611 if foreground else 1.0
    gx = gy = size / 2.0
    accent_r = 20.0 * (size / 512.0) * glyph_scale
    accent_c = (386.0 * (size / 512.0), 126.0 * (size / 512.0))
    accent_c = ((accent_c[0] - size / 2) * glyph_scale + gx,
                (accent_c[1] - size / 2) * glyph_scale + gy)

    buf = bytearray(w * h * 4)
    inv = 1.0 / (ss * ss)
    for py in range(h):
        for px in range(w):
            r = g = b = a = 0.0
            for sy in range(ss):
                for sx in range(ss):
                    x = px + (sx + 0.5) / ss
                    y = py + (sy + 0.5) / ss
                    if not foreground and not _in_rounded_rect(x, y, w, h, radius):
                        continue
                    # background
                    br, bg_, bb = _bg_color(x, y, size)
                    sr, sg, sb = br, bg_, bb
                    sa = 1.0
                    if foreground:
                        sa = 0.0
                    # glyph coordinates in SVG space (512)
                    if foreground:
                        # Adaptive foreground: the glyph is scaled around the
                        # canvas centre to stay inside the 66dp safe zone.
                        u = (x - gx) / glyph_scale + 256.0
                        v = (y - gy) / glyph_scale + 256.0
                    else:
                        # Legacy icon: the 512x512 SVG box maps to the canvas.
                        u = x * (512.0 / size)
                        v = y * (512.0 / size)
                    inside = _point_in_poly(u, v, A_OUTER) and not _point_in_poly(u, v, A_HOLE)
                    if inside:
                        t = max(0.0, min(1.0, (u / 512.0 + v / 512.0) / 2.0))
                        sr, sg, sb = _lerp(GLYPH_TOP, GLYPH_BOT, t)
                        sa = 1.0
                    # accent dot
                    adx = x - accent_c[0]
                    ady = y - accent_c[1]
                    if adx * adx + ady * ady <= accent_r * accent_r:
                        inner = accent_r * 0.45
                        if adx * adx + ady * ady <= inner * inner:
                            # SVG: white at 90% opacity over the cyan dot
                            sr = int(ACCENT[0] + (255 - ACCENT[0]) * 0.9)
                            sg = int(ACCENT[1] + (255 - ACCENT[1]) * 0.9)
                            sb = int(ACCENT[2] + (255 - ACCENT[2]) * 0.9)
                        else:
                            sr, sg, sb = ACCENT
                        sa = 0.95 if not foreground else 1.0
                    r += sr * sa
                    g += sg * sa
                    b += sb * sa
                    a += sa
            i = (py * w + px) * 4
            if a > 0:
                buf[i] = int(r / a)
                buf[i + 1] = int(g / a)
                buf[i + 2] = int(b / a)
                buf[i + 3] = int(255 * a * inv)
            else:
                buf[i + 3] = 0
    return bytes(buf)


def _poly_mask(u, v, poly):
    """Even-odd point-in-polygon test, vectorised."""
    inside = _np.zeros(u.shape, dtype=bool)
    count = len(poly)
    for i in range(count):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % count]
        crosses = (y1 > v) != (y2 > v)
        if not crosses.any():
            continue
        with _np.errstate(divide="ignore", invalid="ignore"):
            xint = (x2 - x1) * (v - y1) / (y2 - y1) + x1
        inside ^= crosses & (u < xint)
    return inside


def _render_numpy(size, foreground=False, ss=4):
    """Vectorised twin of _render_python - same geometry, same output."""
    np = _np
    w = h = size
    radius = 112.0 * (size / 512.0)
    glyph_scale = 0.611 if foreground else 1.0
    gx = gy = size / 2.0
    accent_r = 20.0 * (size / 512.0) * glyph_scale
    acx = 386.0 * (size / 512.0)
    acy = 126.0 * (size / 512.0)
    accent_c = ((acx - gx) * glyph_scale + gx, (acy - gy) * glyph_scale + gy)

    n = size * ss
    xs = (np.arange(n, dtype=np.float64) + 0.5) / ss
    out = np.zeros((size, size, 4), dtype=np.float64)

    c_bg_top = np.array(BG_TOP, dtype=np.float64)
    c_bg_mid = np.array(BG_MID, dtype=np.float64)
    c_bg_bot = np.array(BG_BOT, dtype=np.float64)
    c_g_top = np.array(GLYPH_TOP, dtype=np.float64)
    c_g_bot = np.array(GLYPH_BOT, dtype=np.float64)
    c_accent = np.array(ACCENT, dtype=np.float64)
    c_inner = c_accent + (255.0 - c_accent) * 0.9

    band = max(1, 4_000_000 // max(1, ss * n))
    for row0 in range(0, size, band):
        row1 = min(size, row0 + band)
        y_idx = np.arange(row0 * ss, row1 * ss, dtype=np.float64)
        y = (y_idx + 0.5) / ss
        x = xs
        X = np.broadcast_to(x, (y.size, x.size))
        Y = np.broadcast_to(y[:, None], (y.size, x.size))

        # background gradient
        t = (X / size + Y / size) / 2.0
        f1 = np.clip(t / 0.55, 0.0, 1.0)[..., None]
        f2 = np.clip((t - 0.55) / 0.45, 0.0, 1.0)[..., None]
        color = np.where((t < 0.55)[..., None], c_bg_top + (c_bg_mid - c_bg_top) * f1,
                         c_bg_mid + (c_bg_bot - c_bg_mid) * f2)
        alpha = np.ones((y.size, x.size), dtype=np.float64)

        if foreground:
            alpha[:] = 0.0
            u = (X - gx) / glyph_scale + 256.0
            v = (Y - gy) / glyph_scale + 256.0
        else:
            cx = np.clip(X, radius, w - radius)
            cy = np.clip(Y, radius, h - radius)
            inside_rect = ((X - cx) ** 2 + (Y - cy) ** 2) <= radius * radius
            alpha = inside_rect.astype(np.float64)
            u = X * (512.0 / size)
            v = Y * (512.0 / size)

        inside = _poly_mask(u, v, A_OUTER) & ~_poly_mask(u, v, A_HOLE)
        if inside.any():
            tg = np.clip((u / 512.0 + v / 512.0) / 2.0, 0.0, 1.0)[..., None]
            glyph = c_g_top + (c_g_bot - c_g_top) * tg
            color = np.where(inside[..., None], glyph, color)
            alpha = np.where(inside, 1.0, alpha)

        adx = X - accent_c[0]
        ady = Y - accent_c[1]
        dist2 = adx * adx + ady * ady
        dot = dist2 <= accent_r * accent_r
        if dot.any():
            inner = dist2 <= (accent_r * 0.45) ** 2
            dot_color = np.where(inner[..., None], c_inner, c_accent)
            color = np.where(dot[..., None], dot_color, color)
            alpha = np.where(dot, 0.95 if not foreground else 1.0, alpha)

        shape = (row1 - row0, ss, size, ss)
        a_sum = alpha.reshape(shape).sum(axis=(1, 3))
        safe = np.maximum(a_sum, 1e-9)
        for channel in range(3):
            weighted = (color[..., channel] * alpha).reshape(shape).sum(axis=(1, 3))
            out[row0:row1, :, channel] = weighted / safe
        out[row0:row1, :, 3] = 255.0 * a_sum / (ss * ss)

    rgba = np.zeros((size, size, 4), dtype=np.uint8)
    for channel in range(3):
        rgba[..., channel] = np.clip(np.rint(out[..., channel]), 0, 255).astype(np.uint8)
    rgba[..., 3] = np.clip(np.rint(out[..., 3]), 0, 255).astype(np.uint8)
    return rgba.tobytes()


def render(size, foreground=False, ss=4):
    """Return RGBA bytes for one icon at `size` px."""
    if _np is not None:
        return _render_numpy(size, foreground, ss)
    return _render_python(size, foreground, ss)


def _png_chunk(tag, data):
    c = tag + data
    return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)


def write_png(path, size, rgba):
    raw = b"".join(b"\x00" + rgba[y * size * 4:(y + 1) * size * 4] for y in range(size))
    png = (b"\x89PNG\r\n\x1a\n"
           + _png_chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
           + _png_chunk(b"IDAT", zlib.compress(raw, 9))
           + _png_chunk(b"IEND", b""))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)
    print("wrote", os.path.relpath(path, ROOT))


def try_vector_render(svg, png, size):
    """Prefer a real SVG rasterizer when one is installed."""
    for cmd in (["rsvg-convert", "-w", str(size), "-h", str(size), svg, "-o", png],
                ["inkscape", svg, "--export-type=png", f"--export-filename={png}",
                 "--export-width=%d" % size, "--export-height=%d" % size]):
        if shutil.which(cmd[0]):
            subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            print("wrote", os.path.relpath(png, ROOT), f"(via {cmd[0]})")
            return True
    try:
        import cairosvg  # noqa
        cairosvg.svg2png(url=svg, write_to=png, output_width=size, output_height=size)
        print("wrote", os.path.relpath(png, ROOT), "(via cairosvg)")
        return True
    except Exception:
        return False


def main():
    apply = "--apply" in sys.argv
    brand = os.path.join(ROOT, "docs", "brand")
    logo_preview = os.path.join(brand, "applix-logo-1024.png")
    fg_preview = os.path.join(brand, "applix-icon-foreground-1024.png")

    # Brand previews (vector when possible, built-in renderer as fallback).
    if not try_vector_render(SVG, logo_preview, 1024):
        write_png(logo_preview, 1024, render(1024))
    write_png(fg_preview, 1024, render(1024, foreground=True))

    if not apply:
        print("\nPreviews written. Run with --apply to update Android mipmaps.")
        return

    densities = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    fg_densities = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
    for d, sz in densities.items():
        write_png(os.path.join(RES, f"mipmap-{d}", "ic_launcher.png"), sz, render(sz))
        write_png(os.path.join(RES, f"mipmap-{d}", "ic_launcher_round.png"), sz, render(sz))
    for d, sz in fg_densities.items():
        write_png(os.path.join(RES, f"mipmap-{d}", "ic_launcher_foreground.png"), sz, render(sz, foreground=True))
    # 192px covers the 44dp logo shown in the Flutter UI on 3x/4x density screens.
    write_png(os.path.join(ASSETS, "ic_launcher.png"), 192, render(192))
    print("\nApplied Applix icons to Android resources.")



if __name__ == "__main__":
    main()
