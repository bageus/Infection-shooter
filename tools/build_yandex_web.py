#!/usr/bin/env python3
"""Build the Yandex Games web package at a size the platform accepts.

Yandex Games caps the uncompressed game files at 100 MB. The Web Yandex preset
exports every imported resource, so this script works on a staging copy of the
project instead of the repository: textures are halved in each dimension, OGG
music and sound effects are re-encoded at a lower bitrate, and JSON data is
minified. The repository's assets, and the itch and desktop presets, stay
untouched.

Usage: python3 tools/build_yandex_web.py [--out build/yandex] [--ogg-quality 3]
Needs Godot 4.7.2 on PATH with export templates, Pillow and ffmpeg.
"""

from __future__ import annotations

import argparse
import json
import concurrent.futures
import re
import shutil
import subprocess
from pathlib import Path

from PIL import Image, UnidentifiedImageError

ROOT = Path(__file__).resolve().parent.parent
STAGING = ROOT / "build" / "yandex_staging"
PRESET = "Web Yandex"
IGNORED = shutil.ignore_patterns(".git", ".godot", "build", "export")
SIZE_LINE = re.compile(r"^process/size_limit=(\d+)$", re.MULTILINE)
SOURCE_LINE = re.compile(r'^source_file="res://(.+)"$', re.MULTILINE)
# Biomass atlases are read at fixed pixel cells (biomass_atlas.gd), so they keep full size.
KEEP_FULL_SIZE = ("assets/biomass/",)


def run(*args: str) -> None:
    subprocess.run(args, check=True, cwd=STAGING)


def halve_textures() -> int:
    """Halve each texture: process/size_limit becomes half its effective longest side."""
    count = 0
    for import_file in STAGING.rglob("*.import"):
        text = import_file.read_text(encoding="utf-8")
        size = SIZE_LINE.search(text)
        if 'importer="texture"' not in text or size is None:
            continue
        source = SOURCE_LINE.search(text)
        if source is None:
            continue
        if source.group(1).startswith(KEEP_FULL_SIZE):
            continue
        path = STAGING / source.group(1)
        if not path.is_file():
            continue  # stale import entries whose source is not in the repository
        try:
            width, height = Image.open(path).size
        except UnidentifiedImageError:
            continue  # SVG and other non-raster sources keep their import settings
        cap = int(size.group(1)) or max(width, height)  # 0 means no limit
        limit = min(cap, max(width, height)) // 2
        if limit < 2:
            continue
        import_file.write_text(
            SIZE_LINE.sub(f"process/size_limit={limit}", text), encoding="utf-8"
        )
        count += 1
    return count


def minify_json() -> int:
    """Drop the indentation from the game's JSON data; parsing gives the same values."""
    files = sorted((STAGING / "game").rglob("*.json"))
    for path in files:
        data = json.loads(path.read_text(encoding="utf-8"))
        path.write_text(json.dumps(data, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    return len(files)


def reencode_ogg(path: Path, quality: int) -> None:
    temp = path.with_suffix(".tmp.ogg")
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", str(path), "-c:a", "libvorbis",
         "-q:a", str(quality), str(temp)],
        check=True,
    )
    temp.replace(path)


def reencode_all_ogg(quality: int) -> int:
    files = sorted(STAGING.rglob("*.ogg"))
    with concurrent.futures.ThreadPoolExecutor() as pool:
        list(pool.map(lambda path: reencode_ogg(path, quality), files))
    return len(files)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", default="build/yandex", help="output folder under the repository")
    parser.add_argument("--ogg-quality", type=int, default=3, help="libvorbis -q:a value, 0 to 10")
    args = parser.parse_args()

    if STAGING.exists():
        shutil.rmtree(STAGING)
    shutil.copytree(ROOT, STAGING, ignore=IGNORED)
    print(f"textures halved: {halve_textures()}")
    print(f"ogg re-encoded: {reencode_all_ogg(args.ogg_quality)}")
    print(f"json minified: {minify_json()}")

    run("godot", "--headless", "--path", ".", "--editor", "--quit")
    (STAGING / "build" / "yandex").mkdir(parents=True)
    run("godot", "--headless", "--path", ".", "--export-release", PRESET, "build/yandex/index.html")

    out = ROOT / args.out
    if out.exists():
        shutil.rmtree(out)
    shutil.copytree(STAGING / "build" / "yandex", out)
    shutil.rmtree(STAGING)
    print(f"package: {out} ({sum(f.stat().st_size for f in out.rglob('*') if f.is_file()) / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
