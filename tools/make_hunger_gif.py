#!/usr/bin/env python3
"""Joins tools/capture_hunger_states.gd frames into one GIF and per-scenario contact sheets."""
import sys
from pathlib import Path

from PIL import Image

src = Path(sys.argv[1])
out = Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
frames = []
for scenario in ["rest", "aggro", "crawl", "feed", "flinch"]:
    files = sorted(src.glob(f"{scenario}_*.png"))
    images = [Image.open(f).convert("RGB") for f in files]
    frames += images
    picks = [images[int(i * (len(images) - 1) / 7)] for i in range(8)]
    sheet = Image.new("RGB", (240 * 4, 180 * 2))
    for index, image in enumerate(picks):
        sheet.paste(image.resize((240, 180)), ((index % 4) * 240, (index // 4) * 180))
    sheet.save(out / f"hunger_{scenario}.png")
frames[0].save(out / "hunger_states.gif", save_all=True, append_images=[f.resize((360, 270)) if False else f for f in frames[1:]], duration=66, loop=0, optimize=True)
print(len(frames), "frames")
