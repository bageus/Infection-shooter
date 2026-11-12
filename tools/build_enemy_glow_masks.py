"""Builds <Enemy>_glow.png masks from the albedo texture and the UV rasters.

Run tools/dump_enemy_uv_rasters.gd first, then:
    python3 tools/build_enemy_glow_masks.py <raster dir>
Channels (read by body_wound.gdshader): R = blister, G = eye, B = alternative blister colour (Horde green).
Colour and brightness live in the <Enemy>_game.tres material. Colossus blisters are keyed by albedo colour
(red patches); Titan, Brute, Revenant and Horde use the geometric bump raster. Eyes are the reddest albedo
pixels inside a narrow height band of the head.
"""
import sys
import numpy as np
from PIL import Image, ImageFilter

DIR = "models/objects/characters/enemy/game/"
SIZE = 1024
# Height band (0..1 inside the top 0.28 m of the model) where the eyes sit; missing = no eyes.
EYE_BAND = {"Hunger": (0.4, 0.6), "Brute": (0.3, 0.5), "Revenant": (0.4, 0.6), "Titan": (0.3, 0.5)}


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
        bump, head, height = ras[..., 0], ras[..., 1], ras[..., 2]
        out = np.zeros((SIZE, SIZE, 3), np.float32)
        skin = (r > 110) & (r >= g) & (g >= b * 0.9) & ~((r > 195) & (g > 185))
        if name != "Hunger":
            if name == "Colossus":
                mask = blur(((r > 1.6 * g) & (r > 110) & (g < 110)).astype(np.float32), 3)
            else:
                lo, hi = np.percentile(bump[skin & (bump > 0)], [82, 96])
                mask = blur(smooth(bump, lo, hi) * skin * (1 - head), 5)  # no glowing scalp
            out[..., 0] = mask
            if name == "Horde":
                cells = np.random.default_rng(7).random((SIZE // 24 + 1, SIZE // 24 + 1)).repeat(24, 0).repeat(24, 1)[:SIZE, :SIZE]
                out[..., 2] = blur(cells, 2) > 0.5
        if name in EYE_BAND:
            lo, hi = EYE_BAND[name]
            t = 2.6 if name == "Hunger" else 1.5  # Hunger's face is bloody, so only the reddest pixels
            eye = (r > 100) & (r > t * g) & (r > t * b) & (head > 0.5) & (height >= lo) & (height <= hi)
            out[..., 1] = blur(eye.astype(np.float32), 1.0) * 1.5
        Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).save(DIR + name + "_glow.png")
        print(name, "blister px", int((out[..., 0] > 0.1).sum()), "eye px", int((out[..., 1] > 0.1).sum()))


main(sys.argv[1])
