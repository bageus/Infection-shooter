"""Builds <Enemy>_glow.png emission masks from the albedo texture and the UV rasters.

Run tools/dump_enemy_uv_rasters.gd first, then:
    python3 tools/build_enemy_glow_masks.py <raster dir>
Blisters: Colossus is keyed by albedo colour (red patches); Titan, Brute,
Revenant and Horde use the geometric bump raster. Eyes are red albedo pixels on the head.
"""
import sys
import numpy as np
from PIL import Image, ImageFilter

DIR = "models/objects/characters/enemy/game/"
SIZE = 1024
EYE = np.array([1.0, 0.16, 0.05])
# name: (blister colour, blister strength); Horde is handled separately (red + green).
BLISTER = {
    "Colossus": ((1.0, 0.1, 0.04), 0.18),
    "Titan": ((0.3, 1.0, 0.12), 0.3),
    "Brute": ((1.0, 0.35, 0.1), 0.2),
    "Revenant": ((0.55, 1.0, 0.25), 0.2),
}
EYES = ["Hunger", "Brute", "Revenant", "Titan"]


def blur(a, r):
    return np.asarray(Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(r))).astype(np.float32) / 255


def smooth(a, lo, hi):
    t = np.clip((a - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


def main(raster_dir):
    for name in ["Colossus", "Titan", "Brute", "Revenant", "Horde", "Hunger"]:
        alb = np.asarray(Image.open(DIR + name + "_albedo.jpg").convert("RGB").resize((SIZE, SIZE))).astype(np.float32)
        r, g, b = alb[..., 0], alb[..., 1], alb[..., 2]
        ras = np.asarray(Image.open(f"{raster_dir}/{name}_raster.png")).astype(np.float32) / 255
        bump, head = ras[..., 0], ras[..., 1]
        out = np.zeros((SIZE, SIZE, 3), np.float32)
        skin = (r > 110) & (r >= g) & (g >= b * 0.9) & ~((r > 195) & (g > 185))
        # Only Colossus blisters have a distinct albedo colour; the rest use the bump raster.
        key = (r > 1.6 * g) & (r > 110) & (g < 110) if name == "Colossus" else None
        if name != "Hunger":
            if key is not None:
                mask = blur(key.astype(np.float32), 3)
            else:
                lo, hi = np.percentile(bump[skin & (bump > 0)], [82, 96])
                mask = blur(smooth(bump, lo, hi) * skin * (1 - head), 5)  # no glowing scalp
            if name == "Horde":
                yy, xx = np.mgrid[0:SIZE, 0:SIZE]
                cell = blur(np.random.default_rng(7).random((SIZE // 24 + 1, SIZE // 24 + 1)).repeat(24, 0).repeat(24, 1)[:SIZE, :SIZE], 2) > 0.5
                for sel, col in ((cell, (1.0, 0.1, 0.04)), (~cell, (0.3, 1.0, 0.12))):
                    out += (mask * sel)[..., None] * np.array(col) * 0.25
            else:
                col, strength = BLISTER[name]
                out += mask[..., None] * np.array(col) * strength
        if name in EYES:
            t = 2.4 if name == "Hunger" else 1.4  # Hunger's face is bloody, so only the reddest pixels
            eye = (r > 100) & (r > t * g) & (r > t * b) & (head > 0.5)
            out = np.maximum(out, blur(eye.astype(np.float32), 1.2)[..., None] * 1.3 * EYE)
        Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).save(DIR + name + "_glow.png")
        print(name, "blister px", int((out.max(axis=2) > 0.1).sum()))


main(sys.argv[1])
