#!/usr/bin/env python3
"""Gives glTF nodes that rest at scale 0 a rest scale of 1.

soldier_animated.glb hides the guns, magazines and props it is not showing with a scale of 0 at rest.
Godot's importer then casts that zero basis to a Quaternion and logs thousands of errors, which fails
the CI import gate. The clips set every one of those scales on each frame, so the rest scale only
shows for the frame before the first clip plays.

    python3 tools/fix_glb_zero_scale.py models/objects/characters/soldier_animated.glb
"""
import json
import struct
import sys


def fix(path: str) -> int:
    data = open(path, "rb").read()
    length = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20:20 + length])
    fixed = 0
    for node in gltf["nodes"]:
        scale = node.get("scale")
        if scale and max(abs(value) for value in scale) < 1e-6:
            node["scale"] = [1.0, 1.0, 1.0]
            fixed += 1
    if fixed:
        text = json.dumps(gltf, separators=(",", ":")).encode()
        text += b" " * ((4 - len(text) % 4) % 4)
        out = data[:12] + struct.pack("<I", len(text)) + data[16:20] + text + data[20 + length:]
        open(path, "wb").write(out[:8] + struct.pack("<I", len(out)) + out[12:])
    return fixed


if __name__ == "__main__":
    for glb in sys.argv[1:]:
        print(f"{glb}: {fix(glb)} node(s) given a rest scale of 1")
