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
import pathlib
import re
import shutil
import sys
import zipfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from build_web_skin_probe import RangedArchive

ROOT = pathlib.Path(__file__).resolve().parents[1]
START = "tools/effects_preview/effects_preview.tscn"
REFERENCE = re.compile(r'res://([^"\'\s)]+?\.(?:gdshaderinc|gdshader|gd|tscn|tres|png|ogg))(?![A-Za-z])')


def closure():
    seen, pending = set(), [START]
    while pending:
        path = pending.pop()
        if path in seen:
            continue
        seen.add(path)
        source = ROOT / path
        if source.suffix in (".gd", ".gdshader", ".gdshaderinc", ".tscn", ".tres"):
            pending.extend(REFERENCE.findall(source.read_text(encoding="utf-8")))
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
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
''')
    (destination / "export_presets.cfg").write_text(f'''[preset.0]
name="Web"
platform="Web"
runnable=true
export_filter="all_resources"
include_filter=""
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
