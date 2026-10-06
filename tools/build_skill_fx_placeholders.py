"""Draws stand-in sheets for the three skill effects whose art is not in the
project yet: the golden stun star, the emerald acid puddles and the
heartbeat heart. Each sheet uses the layout recorded in
game/core/vfx/public/effect_atlases.gd, so the supplied art can replace the
file (or the path) without code changes.

Run once: python3 tools/build_skill_fx_placeholders.py
"""

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "models/objects/textures/FX_skills/placeholder"
CELL = 256


def star_points(cx, cy, outer, inner, turn):
    points = []
    for i in range(10):
        radius = outer if i % 2 == 0 else inner
        angle = turn + i * math.pi / 5.0 - math.pi / 2.0
        points.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))
    return points


def glow(layer, radius):
    blurred = layer.filter(ImageFilter.GaussianBlur(radius))
    return Image.alpha_composite(blurred, layer)


# 8 frames, 4x2: three gold stars circling on a flat ellipse (one full turn).
def stun_stars():
    sheet = Image.new("RGBA", (CELL * 4, CELL * 2))
    for frame in range(8):
        cell = Image.new("RGBA", (CELL, CELL))
        draw = ImageDraw.Draw(cell)
        stars = []
        for k in range(3):
            phase = frame / 8.0 * math.tau + k * math.tau / 3.0
            x = CELL * 0.5 + math.cos(phase) * CELL * 0.33
            y = CELL * 0.5 + math.sin(phase) * CELL * 0.12
            depth = 0.75 + 0.25 * math.sin(phase)
            stars.append((depth, x, y, phase))
        for depth, x, y, phase in sorted(stars):
            size = CELL * 0.13 * depth
            draw.polygon(star_points(x, y, size * 1.12, size * 0.5, phase * 0.5), fill=(120, 70, 0, 255))
            draw.polygon(star_points(x, y, size, size * 0.45, phase * 0.5), fill=(255, 205, 40, 255))
            draw.polygon(star_points(x - size * 0.1, y - size * 0.12, size * 0.45, size * 0.2, phase * 0.5), fill=(255, 248, 190, 255))
        sheet.paste(glow(cell, 6), ((frame % 4) * CELL, (frame // 4) * CELL))
    return sheet


# 4 variants, 4x1: top-down emerald acid puddles with bubbles and a bright rim.
def acid_puddles():
    sheet = Image.new("RGBA", (CELL * 4, CELL))
    rng = random.Random(7)
    for variant in range(4):
        cell = Image.new("RGBA", (CELL, CELL))
        draw = ImageDraw.Draw(cell)
        lobes = [(CELL * 0.5, CELL * 0.5, CELL * 0.3)]
        for _ in range(5 + variant):
            angle = rng.random() * math.tau
            dist = CELL * (0.12 + rng.random() * 0.14)
            lobes.append((CELL * 0.5 + math.cos(angle) * dist, CELL * 0.5 + math.sin(angle) * dist, CELL * (0.08 + rng.random() * 0.1)))
        for x, y, r in lobes:
            draw.ellipse((x - r - 5, y - r - 5, x + r + 5, y + r + 5), fill=(120, 255, 90, 230))
        for x, y, r in lobes:
            draw.ellipse((x - r, y - r, x + r, y + r), fill=(20, 150, 60, 215))
        for x, y, r in lobes:
            draw.ellipse((x - r * 0.6, y - r * 0.6, x + r * 0.6, y + r * 0.6), fill=(40, 200, 80, 220))
        for _ in range(14):
            x = CELL * (0.28 + rng.random() * 0.44)
            y = CELL * (0.28 + rng.random() * 0.44)
            r = 3 + rng.random() * 7
            draw.ellipse((x - r, y - r, x + r, y + r), outline=(190, 255, 150, 255), width=2)
        cell = cell.filter(ImageFilter.GaussianBlur(1.2))
        sheet.paste(glow(cell, 4), (variant * CELL, 0))
    return sheet


def heart_shape(draw, cx, cy, size, fill):
    r = size * 0.28
    draw.ellipse((cx - size * 0.5, cy - size * 0.38, cx - size * 0.5 + 2 * r * 1.1, cy - size * 0.38 + 2 * r * 1.1), fill=fill)
    draw.ellipse((cx + size * 0.5 - 2 * r * 1.1, cy - size * 0.38, cx + size * 0.5, cy - size * 0.38 + 2 * r * 1.1), fill=fill)
    draw.polygon([(cx - size * 0.49, cy - size * 0.1), (cx + size * 0.49, cy - size * 0.1), (cx, cy + size * 0.46)], fill=fill)


# 8 frames, 4x2: a cartoon heart beating twice (lub-dub) per loop.
def heartbeat():
    sheet = Image.new("RGBA", (CELL * 4, CELL * 2))
    scales = [0.78, 0.95, 0.86, 0.92, 0.8, 0.76, 0.75, 0.76]
    for frame, scale in enumerate(scales):
        cell = Image.new("RGBA", (CELL, CELL))
        draw = ImageDraw.Draw(cell)
        size = CELL * 0.8 * scale
        cx, cy = CELL * 0.5, CELL * 0.52
        heart_shape(draw, cx, cy, size * 1.06, (70, 0, 10, 255))
        heart_shape(draw, cx, cy, size, (215, 20, 40, 255))
        heart_shape(draw, cx - size * 0.03, cy - size * 0.05, size * 0.8, (240, 55, 70, 255))
        draw.ellipse((cx - size * 0.32, cy - size * 0.3, cx - size * 0.14, cy - size * 0.16), fill=(255, 210, 215, 255))
        sheet.paste(glow(cell, 5 + 6 * (scale - 0.75)), ((frame % 4) * CELL, (frame // 4) * CELL))
    return sheet


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    stun_stars().save(OUT / "stun_stars_placeholder.png")
    acid_puddles().save(OUT / "acid_puddles_placeholder.png")
    heartbeat().save(OUT / "heartbeat_placeholder.png")


if __name__ == "__main__":
    main()
