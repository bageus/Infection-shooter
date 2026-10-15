#!/usr/bin/env python3
"""Export a small WebGL2 fixture using the exact production skin shaders/pool.
No game assets, SDK or third-party Python dependency is needed. Fetch only the
single-thread Web release template from Godot's published template archive.
"""
import io
import http.client
import pathlib
import shutil
import sys
import time
import urllib.error
import urllib.request
import zipfile

ASSET = "Godot_v4.7.2-stable_export_templates.tpz"
URLS = (
    f"https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/{ASSET}",
    f"https://godot-releases.nbg1.your-objectstorage.com/4.7.2-stable/{ASSET}",
)


class RangedArchive(io.RawIOBase):
    def __init__(self):
        headers, _ = self._request("HEAD")
        self.size = int(headers["Content-Length"])
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
        count = min(count, self.size - self.position)
        if count <= 0:
            return b""
        end = min(self.size, self.position + count) - 1
        _, data = self._request("GET", self.position, end)
        self.position += len(data)
        return data


    def _request(self, method, start=None, end=None):
        last_error = None
        for url in URLS:
            for attempt in range(3):
                headers = {} if method == "HEAD" else {"Range": f"bytes={start}-{end}"}
                try:
                    request = urllib.request.Request(url, method=method, headers=headers)
                    with urllib.request.urlopen(request, timeout=30) as response:
                        if method == "HEAD":
                            if int(response.headers.get("Content-Length", "0")) <= 0:
                                raise ValueError("Template archive size is missing")
                            return response.headers, b""
                        # Reject a host ignoring Range before reading a full TPZ.
                        wanted = f"bytes {start}-{end}/{self.size}"
                        if response.status != 206 or response.headers.get("Content-Range") != wanted:
                            raise ValueError("Template host did not honor the exact byte range")
                        data = response.read()
                        if len(data) != end - start + 1:
                            raise OSError("Incomplete template range response")
                        return response.headers, data
                except (urllib.error.URLError, OSError, ValueError, http.client.HTTPException) as error:
                    last_error = error
                    print(f"Godot template download attempt {attempt + 1} failed: {error}", file=sys.stderr)
                    if isinstance(error, ValueError) or (isinstance(error, urllib.error.HTTPError) and error.code not in (408, 429, 500, 502, 503, 504)):
                        break
                    if attempt < 2:
                        time.sleep(attempt + 1)
        raise RuntimeError("Both official Godot template sources failed") from last_error


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
