#!/usr/bin/env python3
"""Builds normal-map atlases for the game's blood decal textures.

    python tools/build_blood_normals.py [--check]

Reads the game atlases written by tools/build_blood_atlases.gd (512 px cells
listed in blood_decals_45/cells.json), treats alpha and brightness as a height
field, and writes <category>/<category>_normal_atlas_*.png with one 256 px slot
per frame. Slots keep the frame's top-left placement, so the game finds a
frame's normal by scaling its albedo rectangle by 1/2 (blood_texture_library.gd).
--check rebuilds in memory and fails if the committed files are out of date.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

ROOT = Path(__file__).resolve().parent.parent / "models/objects/textures/blood_decals_45"
CATEGORIES = {
    "splatter": ("splatter_atlas_3x3.png", (3, 3)),
    "stain": ("stain_atlas_3x3.png", (3, 3)),
    "smear": ("smear_atlas_3x3.png", (3, 3)),
    "pool": ("pool_atlas_4x2.png", (4, 2)),
    "drops": ("drops_atlas_3x3.png", (3, 3)),
}
BUILT_CELL = 512
NORMAL_CELL = 256
# Blur turns the alpha edge into a rounded bevel; STRENGTH scales slope to normal tilt.
BLUR_SIGMA = 2.0
STRENGTH = 3.0
DEPTH_FROM_BRIGHTNESS = 0.45


def height_field(slot: np.ndarray) -> np.ndarray:
    """Height from alpha (blurred for soft edges), deeper where the blood is darker."""
    alpha = slot[..., 3] / 255.0
    rgb = slot[..., :3] / 255.0
    brightness = rgb.mean(axis=2)
    depth = (1.0 - DEPTH_FROM_BRIGHTNESS) + DEPTH_FROM_BRIGHTNESS * (1.0 - brightness)
    return gaussian_filter(alpha * depth, BLUR_SIGMA, mode="constant", cval=0.0)


def slot_normals(slot: np.ndarray) -> np.ndarray:
    """Tangent-space normals (OpenGL convention, +Y toward the top row) as float32 HxWx3."""
    height = height_field(slot)
    d_row, d_col = np.gradient(height)
    normal = np.stack([-d_col * STRENGTH, d_row * STRENGTH, np.ones_like(height)], axis=2)
    return normal / np.linalg.norm(normal, axis=2, keepdims=True)


def downsample(normal: np.ndarray) -> np.ndarray:
    """Averages 2x2 blocks and renormalises, so the slot matches the 256 px cell."""
    averaged = normal.reshape(NORMAL_CELL, 2, NORMAL_CELL, 2, 3).mean(axis=(1, 3))
    return averaged / np.linalg.norm(averaged, axis=2, keepdims=True)


def encode(normal: np.ndarray) -> np.ndarray:
    return np.clip(normal * 0.5 + 0.5, 0.0, 1.0) * 255.0


def build_category(category: str, albedo: np.ndarray, sizes: list, grid: tuple[int, int]) -> np.ndarray:
    columns, rows = grid
    # Flat normal (0, 0, 1) everywhere a frame is absent, in 0..255 encoding.
    output = np.zeros((rows * NORMAL_CELL, columns * NORMAL_CELL, 3), dtype=np.float32)
    output[..., 0:2] = 127.5
    output[..., 2] = 255.0
    for index, (width, height) in enumerate(sizes):
        if width <= 0 or height <= 0:
            continue
        x0 = (index % columns) * BUILT_CELL
        y0 = (index // columns) * BUILT_CELL
        slot = albedo[y0 : y0 + BUILT_CELL, x0 : x0 + BUILT_CELL].astype(np.float32)
        # Each slot is blurred on its own so neighbouring frames never bleed into it.
        normal = downsample(slot_normals(slot))
        # Keep only the used rectangle, placed top-left like the albedo frame.
        used_w = math.ceil(width / 2)
        used_h = math.ceil(height / 2)
        out_x = (index % columns) * NORMAL_CELL
        out_y = (index // columns) * NORMAL_CELL
        output[out_y : out_y + used_h, out_x : out_x + used_w] = encode(normal[:used_h, :used_w])
    return output.astype(np.uint8)


def normal_path(category: str, file: str) -> Path:
    return ROOT / category / file.replace("_atlas_", "_normal_atlas_")


def build(check: bool) -> int:
    cells = json.loads((ROOT / "cells.json").read_text())
    stale = []
    for category, (file, grid) in CATEGORIES.items():
        albedo = np.array(Image.open(ROOT / category / file).convert("RGBA"))
        result = build_category(category, albedo, cells[category], grid)
        target = normal_path(category, file)
        if check:
            current = np.array(Image.open(target).convert("RGB")) if target.exists() else None
            if current is None or not np.array_equal(current, result):
                stale.append(target.name)
            continue
        Image.fromarray(result, "RGB").save(target, optimize=True)
        print(f"{category}: {target.name} {result.shape[1]}x{result.shape[0]}")
    if stale:
        print("Out of date: " + ", ".join(stale) + " (run tools/build_blood_normals.py)")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(build(check="--check" in sys.argv[1:]))
