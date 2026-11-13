"""Builds Colossus_glow.png, the blister mask read by body_wound.gdshader (R = blister).

    python3 tools/build_enemy_glow_masks.py
The Colossus blisters are the saturated red patches of its albedo texture. Colour and brightness live in
Colossus_game.tres (emission, emission_energy_multiplier). Other enemies do not glow.
"""
import numpy as np
from PIL import Image, ImageFilter

DIR = "models/objects/characters/enemy/game/"
SIZE = 1024

alb = np.asarray(Image.open(DIR + "Colossus_albedo.jpg").convert("RGB").resize((SIZE, SIZE))).astype(np.float32)
r, g = alb[..., 0], alb[..., 1]
key = ((r > 1.6 * g) & (r > 110) & (g < 110)).astype(np.uint8) * 255
mask = np.asarray(Image.fromarray(key).filter(ImageFilter.GaussianBlur(3)))
out = np.zeros((SIZE, SIZE, 3), np.uint8)
out[..., 0] = mask
Image.fromarray(out).save(DIR + "Colossus_glow.png")
