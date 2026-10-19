#!/usr/bin/env python3
"""Generate Applix icon PNGs from the brand mark (no external dependencies).

Usage:
  python3 tools/gen_icons.py            # writes docs/brand/*.png previews
  python3 tools/gen_icons.py --apply    # also updates Android mipmaps + assets

The vector source of truth is docs/brand/applix-logo.svg. If rsvg-convert or
cairosvg is available it is used for a higher-fidelity render; otherwise this
script falls back to its built-in renderer, which implements the same shapes.
"""

import math
import os
import shutil
import struct
import subprocess
import sys
import zlib

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


def _bg_color(y, size):
    t = y / max(1, size - 1)
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


def render(size, foreground=False, ss=4):
    """Return RGBA bytes for one icon at `size` px."""
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
                    br, bg_, bb = _bg_color(y, size)
                    sr, sg, sb = br, bg_, bb
                    sa = 1.0
                    if foreground:
                        sa = 0.0
                    # glyph coordinates in SVG space (512)
                    u = (x - gx) / glyph_scale + 256.0
                    v = (y - gy) / glyph_scale + 256.0
                    inside = _point_in_poly(u, v, A_OUTER) and not _point_in_poly(u, v, A_HOLE)
                    if inside:
                        t = max(0.0, min(1.0, (v - 116.0) / (384.0 - 116.0)))
                        sr, sg, sb = _lerp(GLYPH_TOP, GLYPH_BOT, t)
                        sa = 1.0
                    # accent dot
                    adx = x - accent_c[0]
                    ady = y - accent_c[1]
                    if adx * adx + ady * ady <= accent_r * accent_r:
                        inner = accent_r * 0.45
                        if adx * adx + ady * ady <= inner * inner:
                            sr, sg, sb = ACCENT_INNER
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
                 f"--export-width={size}", f"--export-height={size}"]):
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

    # Brand previews (vector when possible, built-in renderer as fallback).
    if not try_vector_render(SVG, os.path.join(brand, "applix-logo-1024.png"), 1024):
        write_png(os.path.join(brand, "applix-logo-1024.png"), 1024, render(1024))
    fg_preview = os.path.join(brand, "applix-icon-foreground-1024.png")
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
    write_png(os.path.join(ASSETS, "ic_launcher.png"), 96, render(96))
    print("\nApplied Applix icons to Android resources.")


if __name__ == "__main__":
    main()
