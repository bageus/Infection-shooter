#!/usr/bin/env python3
"""Shrink the Web export by rewriting .import files in the CI working tree.

Run BEFORE the Godot import step of the Pages workflow only. Never commit the
result: the repository .import files and the desktop build stay untouched.

- textures wider than 512/1024 px get process/size_limit
- lossless atlases (decals, displays) become lossy WebP (UI and logos stay lossless)
- ogg files are re-encoded at lower quality with ffmpeg (if available)
"""
import os
import re
import shutil
import subprocess
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
KEEP_LOSSLESS = ("assets/logo/", "assets/interface/", "assets/icons/")
HERO = ("models/objects/characters/", "models/objects/enviroments/01/")
TEX_EXT = (".png", ".jpg", ".jpeg", ".webp")


def set_param(text, key, value):
    pat = re.compile(r"^" + re.escape(key) + r"=.*$", re.M)
    if pat.search(text):
        return pat.sub(f"{key}={value}", text)
    return text


def tex_dims(path):
    try:
        from PIL import Image
        Image.MAX_IMAGE_PIXELS = None
        return max(Image.open(path).size)
    except Exception:
        return 0


def main():
    stats = {"limit1024": 0, "limit512": 0, "lossy": 0, "ogg": 0}
    for dp, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in (".git", ".godot", "build")]
        for f in files:
            if not f.endswith(".import"):
                continue
            ipath = os.path.join(dp, f)
            src = ipath[:-7]
            rel = os.path.relpath(src, ROOT).replace(os.sep, "/")
            if not src.lower().endswith(TEX_EXT) or not os.path.exists(src):
                continue
            t = open(ipath, encoding="utf-8").read()
            if 'importer="texture"' not in t:
                continue
            o = t
            mx = tex_dims(src)
            small = not rel.startswith(HERO) and not rel.startswith("assets/")
            cap = 512 if small else 1024
            m = re.search(r"^process/size_limit=(\d+)", t, re.M)
            cur = int(m.group(1)) if m else 0
            if mx > cap and (cur == 0 or cur > cap):
                t = set_param(t, "process/size_limit", cap)
                stats["limit512" if cap == 512 else "limit1024"] += 1
            if (re.search(r"^compress/mode=0", t, re.M) and mx >= 512
                    and not rel.startswith(KEEP_LOSSLESS)):
                t = set_param(t, "compress/mode", 1)
                t = set_param(t, "compress/lossy_quality", 0.8)
                stats["lossy"] += 1
            if t != o:
                open(ipath, "w", encoding="utf-8").write(t)
    ff = shutil.which("ffmpeg")
    if ff:
        for dp, dirs, files in os.walk(os.path.join(ROOT, "assets", "audio")):
            for f in files:
                if not f.endswith(".ogg"):
                    continue
                p = os.path.join(dp, f)
                tmp = p + ".tmp.ogg"
                r = subprocess.run([ff, "-y", "-v", "error", "-i", p, "-vn", "-c:a", "libvorbis",
                                    "-q:a", "1", "-map_metadata", "0", tmp])
                if r.returncode == 0 and os.path.getsize(tmp) < os.path.getsize(p):
                    os.replace(tmp, p)
                    stats["ogg"] += 1
                elif os.path.exists(tmp):
                    os.remove(tmp)
    print("web_shrink_imports:", stats)


main()
