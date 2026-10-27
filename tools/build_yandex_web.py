#!/usr/bin/env python3
"""Build the Yandex Games web package at a size the platform accepts.

Yandex Games caps the uncompressed game files at 100 MB. The Web Yandex preset
exports every imported resource, so this script works on a staging copy of the
project instead of the repository: textures are halved in each dimension, OGG
music and sound effects are re-encoded at a lower bitrate, and JSON data is
minified. The repository's assets, and the itch and desktop presets, stay
untouched.

Usage: python3 tools/build_yandex_web.py [--out build/yandex] [--ogg-quality 3]
The asset list tools/yandex_assets.txt is the source files a boot of main.tscn opens,
from: strace -f -e trace=openat godot --headless --path . res://game/bootstrap/app/main.tscn
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
ASSET_LIST = "tools/yandex_assets.txt"
TEXT_SUFFIXES = {".gd", ".tscn", ".tres", ".json", ".gdshader", ".cfg"}


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


def named_in_game() -> set[str]:
    """res:// paths and folder prefixes the game's text names; the trace cannot see paths not taken in one boot."""
    refs: set[str] = set()
    for path in (STAGING / "game").rglob("*"):
        if path.suffix in TEXT_SUFFIXES:
            refs.update(re.findall(r"res://[^\"'\n]+", path.read_text(encoding="utf-8")))
    return refs


def select_resources(preset: str = PRESET) -> int:
    """Export only the game's files and the assets listed in yandex_assets.txt.

    The list is what a traced boot opens (strace on the editor-free run of
    main.tscn); the exporter cannot follow paths the code builds at run time.
    Imported assets ship as their import output, not as raw sources.
    """
    listed = (ROOT / ASSET_LIST).read_text(encoding="utf-8").split()
    files = {f"res://{path.relative_to(STAGING).as_posix()}" for path in (STAGING / "game").rglob("*") if path.is_file()}
    files.update(f"res://{path}" for path in listed if (STAGING / path).is_file())
    for ref in named_in_game():
        target = STAGING / ref[len("res://"):]
        if target.is_file():
            files.add(ref)
        elif ref.endswith("/") and target.is_dir() and ref.startswith("res://assets/"):
            files.update(f"res://{path.relative_to(STAGING).as_posix()}" for path in target.rglob("*") if path.is_file())
    for ref in list(files):
        sibling = STAGING / (ref[len("res://"):] + ".import")
        if sibling.is_file():
            files.discard(ref)
            files.add(f"res://{sibling.relative_to(STAGING).as_posix()}")
            files.update(re.findall(r'"(res://\.godot/imported/[^"]+)"', sibling.read_text(encoding="utf-8")))
    files = sorted(files)
    presets = STAGING / "export_presets.cfg"
    text = presets.read_text(encoding="utf-8")
    block = re.search(r'\[preset\.\d+\]\n\nname="%s"\n.*?(?=\n\[preset\.|\Z)' % re.escape(preset), text, re.S).group(0)
    selection = 'export_filter="resources"\nexport_files=PackedStringArray(%s)' % ", ".join(f'"{f}"' for f in files)
    presets.write_text(text.replace(block, block.replace('export_filter="all_resources"', selection)), encoding="utf-8")
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
    print(f"resources selected: {select_resources()}")
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
