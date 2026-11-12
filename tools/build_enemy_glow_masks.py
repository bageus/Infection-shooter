"""Builds <Enemy>_glow.png masks from the albedo texture and the UV rasters.

Run tools/dump_enemy_uv_rasters.gd first, then:
    python3 tools/build_enemy_glow_masks.py <raster dir>
Channels (read by body_wound.gdshader): R = blister, G = pupil, B = vein.
Colour and brightness live in the <Enemy>_game.tres material and the shader. Colossus blisters are keyed by
albedo colour (red patches); the other blisters use the geometric bump raster or noise blobs on the rest-space
position. Veins are ridged 3D noise on the rest-space position, so they run across texture seams.
Pupils are discs around two fixed 3D points on the face (measured on the Revenant head).
"""
import sys
import numpy as np
from PIL import Image, ImageFilter

DIR = "models/objects/characters/enemy/game/"
SIZE = 1024
# Pupil centres in rest space, measured on each face: x of both eyes and depth below the top of the model.
# The front of the face is +z.
PUPILS = {"Hunger": ((-0.044, 0.040), 0.125), "Brute": ((-0.048, 0.025), 0.165), "Revenant": ((-0.0575, 0.0247), 0.151)}
EYE_RADIUS = 0.0085


def blur(a, r):
    return np.asarray(Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(r))).astype(np.float32) / 255


def smooth(a, lo, hi):
    t = np.clip((a - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


def value_noise(p, seed):
    """Trilinear value noise of an (H, W, 3) array of positions, in 0..1."""
    i = np.floor(p).astype(np.int64)
    f = p - i
    f = f * f * (3 - 2 * f)

    def corner(dx, dy, dz):
        h = (i[..., 0] + dx) * 73856093 ^ (i[..., 1] + dy) * 19349663 ^ (i[..., 2] + dz) * 83492791 ^ seed * 2654435761
        h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
        return (h & 0xFFFF).astype(np.float32) / 65535

    x = lambda a, b: a + (b - a) * f[..., 0]
    y = lambda a, b: a + (b - a) * f[..., 1]
    z = lambda a, b: a + (b - a) * f[..., 2]
    return z(y(x(corner(0, 0, 0), corner(1, 0, 0)), x(corner(0, 1, 0), corner(1, 1, 0))),
             y(x(corner(0, 0, 1), corner(1, 0, 1)), x(corner(0, 1, 1), corner(1, 1, 1))))


def veins(p, freq=9.0, fine=False):
    """Branching lines: the zero set of two noise fields; fine = thinner lines."""
    thin = 1 - np.abs(value_noise(p * freq, 1) * 2 - 1)
    branch = 1 - np.abs(value_noise(p * freq * 2.3, 2) * 2 - 1)
    if fine:
        return np.maximum(smooth(thin, 0.95, 0.985), 0.6 * smooth(branch, 0.97, 0.992))
    return np.maximum(smooth(thin, 0.9, 0.97), 0.8 * smooth(branch, 0.94, 0.985))


def main(raster_dir):
    for name in ["Colossus", "Titan", "Brute", "Revenant", "Horde", "Hunger"]:
        alb = np.asarray(Image.open(DIR + name + "_albedo.jpg").convert("RGB").resize((SIZE, SIZE))).astype(np.float32)
        r, g, b = alb[..., 0], alb[..., 1], alb[..., 2]
        ras = np.asarray(Image.open(f"{raster_dir}/{name}_raster.png")).astype(np.float32) / 255
        bump, head = ras[..., 0], ras[..., 1]
        pos = np.fromfile(f"{raster_dir}/{name}_pos.f32", np.float32).reshape(SIZE, SIZE, 3)
        top = float(open(f"{raster_dir}/{name}_top.txt").read())
        x, y, z = pos[..., 0], pos[..., 1], pos[..., 2]
        mapped = np.abs(pos).sum(axis=2) > 0
        skin = (r > 110) & (r >= g) & (g >= b * 0.9) & ~((r > 195) & (g > 185)) & mapped
        lo, hi = np.percentile(bump[skin & (bump > 0)], [82, 96])
        bumpy = smooth(bump, lo, hi) * skin
        mutated = blur(bumpy, 14) > 0.07  # mutated skin is the bumpy skin; clothes stay out
        arm = np.abs(x) > 0.28
        out = np.zeros((SIZE, SIZE, 3), np.float32)
        blisters = vein = None
        if name == "Colossus":
            blisters = ((r > 1.6 * g) & (r > 110) & (g < 110)).astype(np.float32)
        elif name == "Titan":
            back = (z < -0.1) & (y > -0.1) & (y < 0.8)
            blobs = smooth(value_noise(pos * 9, 3), 0.5, 0.68)
            blisters = np.maximum(bumpy, blobs * 0.9) * back * skin
            vein = veins(pos) * (mutated & arm & ~back)
        elif name == "Brute":
            blisters = bumpy * (head > 0.5)  # the lump on the head
            vein = veins(pos) * (mutated & arm & (head < 0.5))
        elif name == "Revenant":
            vein = veins(pos) * (mutated & (head < 0.5))
        elif name == "Horde":
            blisters = bumpy
            # patchy, not the whole body: green veins here read as too much
            vein = veins(pos, fine=True) * mapped * smooth(value_noise(pos * 3, 5), 0.4, 0.55)
        if blisters is not None:
            out[..., 0] = blur(blisters, 4)
        if vein is not None:
            out[..., 2] = blur(vein.astype(np.float32), 0.7)
        if name in PUPILS:
            eyes = np.zeros((SIZE, SIZE), bool)
            eye_x, below = PUPILS[name]
            for ex in eye_x:
                eyes |= (np.hypot(x - ex, y - (top - below)) < EYE_RADIUS) & (z > 0.07)
            out[..., 1] = blur((eyes & mapped).astype(np.float32), 0.8)
        Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).save(DIR + name + "_glow.png")
        print(name, [int((out[..., c] > 0.1).sum()) for c in range(3)])


main(sys.argv[1])
