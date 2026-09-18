import json
import math
import struct
from pathlib import Path

ROOT = Path("models/objects")


def mat_identity():
    return [
        [1.0, 0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0],
    ]


def mat_mul(a, b):
    out = [[0.0] * 4 for _ in range(4)]
    for r in range(4):
        for c in range(4):
            out[r][c] = sum(a[r][k] * b[k][c] for k in range(4))
    return out


def mat_translate(v):
    m = mat_identity()
    m[0][3], m[1][3], m[2][3] = v
    return m


def mat_scale(v):
    m = mat_identity()
    m[0][0], m[1][1], m[2][2] = v
    return m


def mat_quat(q):
    x, y, z, w = q
    xx, yy, zz = x * x, y * y, z * z
    xy, xz, yz = x * y, x * z, y * z
    wx, wy, wz = w * x, w * y, w * z
    return [
        [1 - 2 * (yy + zz), 2 * (xy - wz), 2 * (xz + wy), 0],
        [2 * (xy + wz), 1 - 2 * (xx + zz), 2 * (yz - wx), 0],
        [2 * (xz - wy), 2 * (yz + wx), 1 - 2 * (xx + yy), 0],
        [0, 0, 0, 1],
    ]


def node_matrix(node):
    if "matrix" in node:
        v = node["matrix"]
        return [[v[c * 4 + r] for c in range(4)] for r in range(4)]
    t = mat_translate(node.get("translation", [0, 0, 0]))
    r = mat_quat(node.get("rotation", [0, 0, 0, 1]))
    s = mat_scale(node.get("scale", [1, 1, 1]))
    return mat_mul(mat_mul(t, r), s)


def transform_point(m, p):
    v = [p[0], p[1], p[2], 1.0]
    return [sum(m[r][c] * v[c] for c in range(4)) for r in range(3)]


def read_json_chunk(path):
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise ValueError("not GLB")
    offset = 12
    while offset < length:
        chunk_len, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        chunk = data[offset:offset + chunk_len]
        offset += chunk_len
        if chunk_type == 0x4E4F534A:
            return json.loads(chunk.decode("utf-8").rstrip("\x00 \t\r\n"))
    raise ValueError("JSON chunk missing")


def mesh_bounds(doc, mesh_index):
    mins = [math.inf, math.inf, math.inf]
    maxs = [-math.inf, -math.inf, -math.inf]
    mesh = doc["meshes"][mesh_index]
    found = False
    for prim in mesh.get("primitives", []):
        pos = prim.get("attributes", {}).get("POSITION")
        if pos is None:
            continue
        acc = doc["accessors"][pos]
        if "min" not in acc or "max" not in acc:
            continue
        found = True
        for i in range(3):
            mins[i] = min(mins[i], acc["min"][i])
            maxs[i] = max(maxs[i], acc["max"][i])
    return (mins, maxs) if found else None


def inspect(path):
    doc = read_json_chunk(path)
    nodes = doc.get("nodes", [])
    parents = {}
    for i, node in enumerate(nodes):
        for child in node.get("children", []):
            parents[child] = i

    cache = {}

    def world_matrix(i):
        if i in cache:
            return cache[i]
        local = node_matrix(nodes[i])
        p = parents.get(i)
        cache[i] = mat_mul(world_matrix(p), local) if p is not None else local
        return cache[i]

    mins = [math.inf, math.inf, math.inf]
    maxs = [-math.inf, -math.inf, -math.inf]
    found = False
    for i, node in enumerate(nodes):
        mesh_index = node.get("mesh")
        if mesh_index is None:
            continue
        bounds = mesh_bounds(doc, mesh_index)
        if bounds is None:
            continue
        found = True
        lo, hi = bounds
        m = world_matrix(i)
        for x in (lo[0], hi[0]):
            for y in (lo[1], hi[1]):
                for z in (lo[2], hi[2]):
                    p = transform_point(m, (x, y, z))
                    for a in range(3):
                        mins[a] = min(mins[a], p[a])
                        maxs[a] = max(maxs[a], p[a])
    if not found:
        return None
    dims = [maxs[i] - mins[i] for i in range(3)]
    tallest = "XYZ"[max(range(3), key=lambda i: dims[i])]
    return dims, tallest


for path in sorted(ROOT.glob("*.glb")):
    try:
        result = inspect(path)
        if result is None:
            print(f"GLB_ORIENTATION {path.name} no_bounds")
            continue
        dims, tallest = result
        print(
            "GLB_ORIENTATION "
            f"{path.name} dims=({dims[0]:.3f},{dims[1]:.3f},{dims[2]:.3f}) "
            f"largest_axis={tallest}"
        )
    except Exception as exc:
        print(f"GLB_ORIENTATION {path.name} ERROR {exc}")
