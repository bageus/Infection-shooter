"""Moves a named node of a .glb to a new translation, keeping the file layout.

    python tools/set_glb_marker.py model.glb Grip_L 0.23 0.022 0.047
"""
import json
import struct
import sys

path, name = sys.argv[1], sys.argv[2]
translation = [float(v) for v in sys.argv[3:6]]
data = bytearray(open(path, "rb").read())
length = struct.unpack("<I", data[12:16])[0]
document = json.loads(data[20:20 + length])
for node in document["nodes"]:
    if node.get("name") == name:
        node["translation"] = translation
        break
else:
    sys.exit("node not found: " + name)
text = json.dumps(document, separators=(",", ":")).encode()
text += b" " * (-len(text) % 4)
tail = data[20 + length:]
header = bytearray(data[:12])
struct.pack_into("<I", header, 8, 12 + 8 + len(text) + len(tail))
open(path, "wb").write(bytes(header) + struct.pack("<I", len(text)) + b"JSON" + text + tail)
