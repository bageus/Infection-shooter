#!/usr/bin/env python3
"""Export a small WebGL2 fixture using the exact production skin shaders/pool.
No game assets, SDK or third-party Python dependency is needed. Fetch only the
single-thread Web release template from Godot's published template archive.
"""
import io
import pathlib
import shutil
import sys
import urllib.request
import zipfile

URL = "https://godot-releases.nbg1.your-objectstorage.com/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"


class RangedArchive(io.RawIOBase):
    def __init__(self):
        with urllib.request.urlopen(urllib.request.Request(URL, method="HEAD"), timeout=60) as response:
            self.size = int(response.headers["Content-Length"])
        self.position = 0

    def seekable(self):
        return True

    def tell(self):
        return self.position

    def seek(self, offset, whence=0):
        self.position = offset if whence == 0 else self.position + offset if whence == 1 else self.size + offset
        return self.position

    def read(self, count=-1):
        if count < 0:
            count = self.size - self.position
        if count == 0:
            return b""
        end = min(self.size, self.position + count) - 1
        request = urllib.request.Request(URL, headers={"Range": f"bytes={self.position}-{end}"})
        with urllib.request.urlopen(request, timeout=120) as response:
            if response.status != 206:
                raise RuntimeError("Template host must honor byte ranges")
            data = response.read()
        self.position += len(data)
        return data


def build(destination):
    repository = pathlib.Path(__file__).resolve().parents[1]
    destination = destination.resolve()
    scripts = destination / "game/features/infected"
    scripts.mkdir(parents=True, exist_ok=True)
    for name in ["body_skin_materials.gd", "body_blood_bake.gd", "body_wound.gdshader", "poison_tint.gdshader"]:
        shutil.copyfile(repository / "game/features/infected" / name, scripts / name)
    shutil.copyfile(repository / "tools/web_skin_probe.gd", destination / "probe.gd")
    template = destination / "web-template.zip"
    with zipfile.ZipFile(RangedArchive()) as archive:
        template.write_bytes(archive.read("templates/web_nothreads_release.zip"))
    (destination / "project.godot").write_text('''config_version=5
[application]
config/name="Skin Web Probe"
run/main_scene="res://probe.tscn"
[display]
window/size/viewport_width=960
window/size/viewport_height=720
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
''')
    (destination / "probe.tscn").write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://probe.gd" id="1"]
[node name="Probe" type="Node3D"]
script = ExtResource("1")
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
