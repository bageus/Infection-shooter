#!/usr/bin/env python3
"""Build a small standalone project around tools/effects_preview and lay it out
for a Web export (single-thread, WebGL2). Only the files the preview scene
reaches through res:// references are copied, so the page stays small and no
mission asset is needed.

  python3 tools/build_effects_preview_web.py /tmp/effects-web
  godot --headless --path /tmp/effects-web --editor --quit
  godot --headless --path /tmp/effects-web --export-release Web build/index.html
  python3 -m http.server -d /tmp/effects-web/build
"""
import json
import pathlib
import re
import struct
import shutil
import sys
import zipfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from build_web_skin_probe import RangedArchive

ROOT = pathlib.Path(__file__).resolve().parents[1]
START = "tools/effects_preview/effects_preview.tscn"
REFERENCE = re.compile(r'res://([^"\'\n]+\.[A-Za-z0-9]+)(?=["\'])')


TEXT = (".gd", ".gdshader", ".gdshaderinc", ".tscn", ".tres", ".json", ".import")
# The staged destructible models need their import plugin and settings to look like in the game.
ADDON = "addons/staged_glb_import"


def glb_files(source):
    """Files a .glb points at (external textures and buffers), relative to the project."""
    data = source.read_bytes()
    length = struct.unpack_from("<I", data, 12)[0]
    header = json.loads(data[20:20 + length])
    names = [item["uri"] for kind in ("images", "buffers") for item in header.get(kind, []) if "uri" in item and not item["uri"].startswith("data:")]
    return [(source.parent / name).relative_to(ROOT).as_posix() for name in names]


# Scripts that build texture paths from a directory constant: ROOT + "paper/atlas.png".
DIRECTORY = re.compile(r'\bROOT\s*(?::=|=)\s*"res://([^"\n]+/)"')
RELATIVE = re.compile(r'\bROOT\s*\+\s*"([^"\n]+)"')


def joined_paths(text):
    return [folder + name for folder in DIRECTORY.findall(text) for name in RELATIVE.findall(text)]


UID = re.compile(r'uid://[a-z0-9]+')


def uid_paths():
    """uid -> project path, from the .import and .uid files beside every asset."""
    found = {}
    for item in ROOT.rglob("*"):
        if item.suffix == ".import" and ".godot" not in item.parts:
            match = re.search(r'^uid="(uid://[a-z0-9]+)"', item.read_text(encoding="utf-8"), re.M)
            target = item.with_suffix("")
        elif item.suffix == ".uid" and ".godot" not in item.parts:
            match, target = UID.search(item.read_text(encoding="utf-8")), item.with_suffix("")
        else:
            continue
        if match:
            found[match.group(1) if match.re is not UID else match.group(0)] = target.relative_to(ROOT).as_posix()
    return found


def closure():
    uids = uid_paths()
    seen = set()
    pending = [START] + sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / ADDON).iterdir() if p.is_file())
    while pending:
        path = pending.pop()
        if path in seen:
            continue
        seen.add(path)
        source = ROOT / path
        if source.suffix in TEXT:
            text = source.read_text(encoding="utf-8")
            pending.extend(p for p in REFERENCE.findall(text) if (ROOT / p).is_file())
            if source.suffix == ".gd":
                pending.extend(p for p in joined_paths(text) if (ROOT / p).is_file())
            pending.extend(uids[u] for u in UID.findall(text) if u in uids)
        elif (ROOT / (path + ".import")).is_file():
            pending.append(path + ".import")
            if source.suffix == ".glb":
                pending.extend(p for p in glb_files(source) if (ROOT / p).is_file())
    return sorted(seen)


def build(destination):
    destination = destination.resolve()
    for path in closure():
        target = destination / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / path, target)
        uid = ROOT / (path + ".uid")
        if uid.exists():
            shutil.copyfile(uid, destination / (path + ".uid"))
    template = destination / "web-template.zip"
    with zipfile.ZipFile(RangedArchive()) as archive:
        template.write_bytes(archive.read("templates/web_nothreads_release.zip"))
    (destination / "project.godot").write_text(f'''config_version=5
[application]
config/name="Effects Preview"
run/main_scene="res://{START}"
config/features=PackedStringArray("4.7", "GL Compatibility")
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
[editor_plugins]
enabled=PackedStringArray("res://{ADDON}/plugin.cfg")
[importer_defaults]
texture={{
"detect_3d/compress_to": 0,
"mipmaps/generate": true
}}
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
''')
    (destination / "export_presets.cfg").write_text(f'''[preset.0]
name="Web"
platform="Web"
runnable=true
export_filter="all_resources"
include_filter="*.json"
exclude_filter="web-template.zip,build/*"
export_path="build/index.html"
script_export_mode=2
[preset.0.options]
custom_template/release="{template}"
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=false
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
''')
    (destination / "build").mkdir(exist_ok=True)


if __name__ == "__main__":
    build(pathlib.Path(sys.argv[1]))
