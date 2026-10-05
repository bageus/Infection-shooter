#!/usr/bin/env python3
"""Re-fracture the breakable glass models into irregular shards.

The supplied breakable glass GLBs split their panes into a regular grid of
equal triangles. This tool replaces every `GlassShard_*` node of the
`Glass_Shards` stage with irregular Voronoi pieces of mixed sizes (clusters
of small splinters among larger plates), cut from each intact glass pane:

  python tools/fracture_glass.py            # all four models, fixed seeds
  python tools/fracture_glass.py --check    # only print the shard summary

Each pane is cut in its own plane and the shards are baked into the space of
the `Glass_Shards` group, so they sit exactly where the glass is, whatever
rotation or scale the pane node has (the glass door's pane is rotated and
scaled; its old shards lay flat). Frames, blinds, materials and textures are
kept; unused buffers are dropped when the file is written back.
Requires numpy.
"""
from __future__ import annotations

import argparse
import json
import math
import struct
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "models" / "objects" / "enviroments" / "01"
TARGETS = {
    "01_glass_wall_full_breakable.glb": 1101,
    "01_glass_partition_half_breakable.glb": 1102,
    "01_glass_partition_blinds_breakable.glb": 1103,
    "01_glass_door_breakable.glb": 1104,
}
COMPONENT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}


# ----------------------------------------------------------------- glb i/o

def read_glb(path: Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    json_length = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20:20 + json_length])
    offset = 20 + json_length
    binary = b""
    if offset < len(data):
        bin_length = struct.unpack("<I", data[offset:offset + 4])[0]
        binary = data[offset + 8:offset + 8 + bin_length]
    return gltf, binary


def write_glb(path: Path, gltf: dict, binary: bytes) -> None:
    gltf["buffers"] = [{"byteLength": len(binary)}]
    text = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    text += b" " * ((4 - len(text) % 4) % 4)
    binary += b"\0" * ((4 - len(binary) % 4) % 4)
    total = 12 + 8 + len(text) + 8 + len(binary)
    out = struct.pack("<III", 0x46546C67, 2, total)
    out += struct.pack("<II", len(text), 0x4E4F534A) + text
    out += struct.pack("<II", len(binary), 0x004E4942) + binary
    path.write_bytes(out)


def accessor(gltf: dict, binary: bytes, index: int) -> np.ndarray:
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    width = WIDTH[acc["type"]]
    dtype = np.dtype(COMPONENT[acc["componentType"]])
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = view.get("byteStride", 0) or dtype.itemsize * width
    rows = []
    for i in range(acc["count"]):
        rows.append(np.frombuffer(binary, dtype=dtype, count=width, offset=start + i * stride))
    return np.array(rows).reshape(acc["count"], width)


def local_matrix(node: dict) -> np.ndarray:
    if "matrix" in node:
        return np.array(node["matrix"], dtype=float).reshape(4, 4).T
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    rotation = np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])
    scale = np.array(node.get("scale", [1, 1, 1]), dtype=float)
    # Hidden damage stages use zero scale; geometry is placed as if shown.
    if np.all(np.abs(scale) < 1e-9):
        scale = np.ones(3)
    matrix = np.eye(4)
    matrix[:3, :3] = rotation * scale
    matrix[:3, 3] = node.get("translation", [0, 0, 0])
    return matrix


def world_matrices(gltf: dict) -> dict[int, np.ndarray]:
    result: dict[int, np.ndarray] = {}

    def walk(index: int, parent: np.ndarray) -> None:
        matrix = parent @ local_matrix(gltf["nodes"][index])
        result[index] = matrix
        for child in gltf["nodes"][index].get("children", []):
            walk(child, matrix)

    for scene in gltf.get("scenes", []):
        for root in scene.get("nodes", []):
            walk(root, np.eye(4))
    return result


def parents(gltf: dict) -> dict[int, int]:
    return {child: index for index, node in enumerate(gltf["nodes"]) for child in node.get("children", [])}


def find_named(gltf: dict, name: str) -> int:
    for index, node in enumerate(gltf["nodes"]):
        if node.get("name") == name:
            return index
    return -1


def subtree(gltf: dict, index: int) -> list[int]:
    out = [index]
    for child in gltf["nodes"][index].get("children", []):
        out += subtree(gltf, child)
    return out


# ------------------------------------------------------------- fracturing

def clip(polygon: list[np.ndarray], point: np.ndarray, normal: np.ndarray) -> list[np.ndarray]:
    """Keep the part of a convex polygon where (p - point) . normal <= 0."""
    out: list[np.ndarray] = []
    for i, current in enumerate(polygon):
        nxt = polygon[(i + 1) % len(polygon)]
        a = float(np.dot(current - point, normal))
        b = float(np.dot(nxt - point, normal))
        if a <= 0:
            out.append(current)
        if (a < 0 < b) or (b < 0 < a):
            out.append(current + (nxt - current) * (a / (a - b)))
    return out


def seeds_for(width: float, height: float, rng: np.random.Generator) -> np.ndarray:
    """Mixed-size layout: a few dense clusters of splinters among sparse plates."""
    area = width * height
    plates = int(np.clip(area * 3.2, 7, 18))
    points = [rng.uniform([0, 0], [width, height]) for _ in range(plates)]
    for _ in range(int(np.clip(area * 0.9, 2, 5))):
        center = rng.uniform([width * 0.12, height * 0.12], [width * 0.88, height * 0.88])
        spread = rng.uniform(0.09, 0.2)
        for _ in range(rng.integers(4, 8)):
            points.append(center + rng.normal(0, spread, 2))
    # Keep inside the pane and drop near-duplicates that would cut slivers.
    kept: list[np.ndarray] = []
    for p in points:
        p = np.clip(p, [0.02, 0.02], [width - 0.02, height - 0.02])
        if all(np.linalg.norm(p - q) > 0.075 for q in kept):
            kept.append(p)
    return np.array(kept)


def voronoi_cells(width: float, height: float, seeds: np.ndarray, rng: np.random.Generator) -> list[list[np.ndarray]]:
    rectangle = [np.array([0.0, 0.0]), np.array([width, 0.0]), np.array([width, height]), np.array([0.0, height])]
    cells = []
    for i, seed in enumerate(seeds):
        cell = rectangle
        for j, other in enumerate(seeds):
            if i == j:
                continue
            # A slightly shifted bisector keeps the edges from looking machine-cut.
            middle = (seed + other) * 0.5 + rng.normal(0, 0.006, 2)
            cell = clip(cell, middle, other - seed)
            if len(cell) < 3:
                break
        if len(cell) >= 3 and polygon_area(cell) > 1e-4:
            cells.append(cell)
    return cells


def polygon_area(polygon: list[np.ndarray]) -> float:
    area = 0.0
    for i, a in enumerate(polygon):
        b = polygon[(i + 1) % len(polygon)]
        area += a[0] * b[1] - b[0] * a[1]
    return abs(area) * 0.5


class Pane:
    """A glass pane: local box, its plane axes and a world mapping."""

    def __init__(self, gltf: dict, binary: bytes, node: int, matrix: np.ndarray):
        mesh = gltf["meshes"][gltf["nodes"][node]["mesh"]]
        # A pane mesh may also carry a handle or trim as extra primitives; the
        # glass is the primitive with the largest flat extent.
        best = None
        for primitive in mesh["primitives"]:
            p = accessor(gltf, binary, primitive["attributes"]["POSITION"])
            extent = np.sort((p.max(0) - p.min(0)) * np.linalg.norm(matrix[:3, :3], axis=0))
            score = extent[1] * extent[2]
            if best is None or score > best[0]:
                best = (score, primitive, p)
        _, primitive, points = best
        uvs = []
        if "TEXCOORD_0" in primitive["attributes"]:
            uvs.append((points, accessor(gltf, binary, primitive["attributes"]["TEXCOORD_0"])))
        self.low = points.min(0)
        self.high = points.max(0)
        self.matrix = matrix
        extent_local = self.high - self.low
        scaled = extent_local * np.linalg.norm(matrix[:3, :3], axis=0)
        self.thin = int(np.argmin(scaled))
        self.axes = [a for a in range(3) if a != self.thin]
        self.size = np.array([scaled[self.axes[0]], scaled[self.axes[1]]])
        self.scale = np.linalg.norm(matrix[:3, :3], axis=0)
        self.uv = self._fit_uv(uvs)

    def _fit_uv(self, uvs) -> np.ndarray | None:
        if not uvs:
            return None
        p = np.vstack([u[0] for u in uvs])
        t = np.vstack([u[1] for u in uvs])
        design = np.c_[p[:, self.axes[0]], p[:, self.axes[1]], np.ones(len(p))]
        solution, *_ = np.linalg.lstsq(design, t, rcond=None)
        return solution

    def to_local(self, u: float, v: float, side: float) -> np.ndarray:
        point = np.zeros(3)
        point[self.axes[0]] = self.low[self.axes[0]] + u / self.scale[self.axes[0]]
        point[self.axes[1]] = self.low[self.axes[1]] + v / self.scale[self.axes[1]]
        middle = (self.low[self.thin] + self.high[self.thin]) * 0.5
        half = (self.high[self.thin] - self.low[self.thin]) * 0.5
        point[self.thin] = middle + side * half
        return point

    def uv_at(self, local: np.ndarray) -> np.ndarray:
        if self.uv is None:
            return np.zeros(2)
        return np.array([local[self.axes[0]], local[self.axes[1]], 1.0]) @ self.uv


def shard_mesh(pane: Pane, cell: list[np.ndarray], to_group: np.ndarray):
    """Extruded convex cell -> flat-shaded triangles in Glass_Shards space."""
    transform = to_group @ pane.matrix
    normal_matrix = np.linalg.inv(transform[:3, :3]).T

    def place(local: np.ndarray) -> np.ndarray:
        return (transform @ np.r_[local, 1.0])[:3]

    def direction(local_normal: np.ndarray) -> np.ndarray:
        n = normal_matrix @ local_normal
        return n / (np.linalg.norm(n) or 1.0)

    front = [pane.to_local(p[0], p[1], 1.0) for p in cell]
    back = [pane.to_local(p[0], p[1], -1.0) for p in cell]
    positions, normals, uvs, indices = [], [], [], []

    def face(points: list[np.ndarray], local_normal: np.ndarray, reverse: bool) -> None:
        start = len(positions)
        n = direction(local_normal)
        for p in points:
            positions.append(place(p))
            normals.append(n)
            uvs.append(pane.uv_at(p))
        for k in range(1, len(points) - 1):
            tri = [start, start + k, start + k + 1]
            indices.extend(tri[::-1] if reverse else tri)

    thin_normal = np.zeros(3)
    thin_normal[pane.thin] = 1.0
    face(front, thin_normal, False)
    face(back, -thin_normal, True)
    for i in range(len(cell)):
        j = (i + 1) % len(cell)
        edge = cell[j] - cell[i]
        outward2 = np.array([edge[1], -edge[0]])
        local_normal = np.zeros(3)
        local_normal[pane.axes[0]] = outward2[0]
        local_normal[pane.axes[1]] = outward2[1]
        face([front[i], front[j], back[j], back[i]], local_normal, False)
    positions = np.array(positions, dtype=np.float32)
    # Winding follows the outward normal so both renderers cull correctly.
    tris = np.array(indices, dtype=np.uint32).reshape(-1, 3)
    normals = np.array(normals, dtype=np.float32)
    for t in tris:
        a, b, c = positions[t]
        if np.dot(np.cross(b - a, c - a), normals[t[0]]) < 0:
            t[1], t[2] = t[2], t[1]
    return positions, normals, np.array(uvs, dtype=np.float32), tris.reshape(-1)


# --------------------------------------------------------------- rewrite

class Writer:
    def __init__(self, gltf: dict, binary: bytes):
        self.gltf = gltf
        self.binary = bytearray(binary)

    def add(self, array: np.ndarray, component: int, kind: str, target: int, bounds: bool = False) -> int:
        while len(self.binary) % 4:
            self.binary.append(0)
        data = array.tobytes()
        self.gltf["bufferViews"].append({"buffer": 0, "byteOffset": len(self.binary), "byteLength": len(data), "target": target})
        self.binary += data
        acc = {"bufferView": len(self.gltf["bufferViews"]) - 1, "componentType": component, "count": int(len(array)), "type": kind}
        if bounds:
            acc["min"] = array.min(0).tolist()
            acc["max"] = array.max(0).tolist()
        self.gltf["accessors"].append(acc)
        return len(self.gltf["accessors"]) - 1


def compact(gltf: dict, binary: bytes) -> tuple[dict, bytes]:
    """Drop nodes, meshes, accessors and buffer views nothing uses any more."""
    reachable: list[int] = []
    for scene in gltf["scenes"]:
        for root in scene.get("nodes", []):
            reachable += subtree(gltf, root)
    node_map = {old: new for new, old in enumerate(sorted(set(reachable)))}
    nodes = []
    for old in sorted(node_map):
        node = dict(gltf["nodes"][old])
        if "children" in node:
            node["children"] = [node_map[c] for c in node["children"] if c in node_map]
        nodes.append(node)
    for scene in gltf["scenes"]:
        scene["nodes"] = [node_map[n] for n in scene.get("nodes", []) if n in node_map]
    assert not gltf.get("skins") and not gltf.get("animations"), "skins/animations are not remapped"
    used_meshes = sorted({n["mesh"] for n in nodes if "mesh" in n})
    mesh_map = {old: new for new, old in enumerate(used_meshes)}
    for node in nodes:
        if "mesh" in node:
            node["mesh"] = mesh_map[node["mesh"]]
    meshes = [gltf["meshes"][m] for m in used_meshes]
    used_accessors: set[int] = set()
    for mesh in meshes:
        for primitive in mesh["primitives"]:
            used_accessors.update(primitive["attributes"].values())
            if "indices" in primitive:
                used_accessors.add(primitive["indices"])
    accessor_map = {old: new for new, old in enumerate(sorted(used_accessors))}
    for mesh in meshes:
        for primitive in mesh["primitives"]:
            primitive["attributes"] = {k: accessor_map[v] for k, v in primitive["attributes"].items()}
            if "indices" in primitive:
                primitive["indices"] = accessor_map[primitive["indices"]]
    accessors = [gltf["accessors"][a] for a in sorted(used_accessors)]
    used_views = sorted({a["bufferView"] for a in accessors if "bufferView" in a} | {i["bufferView"] for i in gltf.get("images", []) if "bufferView" in i})
    view_map = {}
    out = bytearray()
    views = []
    for new, old in enumerate(used_views):
        view = dict(gltf["bufferViews"][old])
        while len(out) % 4:
            out.append(0)
        start = view.get("byteOffset", 0)
        chunk = binary[start:start + view["byteLength"]]
        view["byteOffset"] = len(out)
        out += chunk
        views.append(view)
        view_map[old] = new
    for acc in accessors:
        if "bufferView" in acc:
            acc["bufferView"] = view_map[acc["bufferView"]]
    for image in gltf.get("images", []):
        if "bufferView" in image:
            image["bufferView"] = view_map[image["bufferView"]]
    gltf.update(nodes=nodes, meshes=meshes, accessors=accessors, bufferViews=views)
    return gltf, bytes(out)


def fracture(path: Path, seed: int, check_only: bool) -> None:
    gltf, binary = read_glb(path)
    rng = np.random.default_rng(seed)
    world = world_matrices(gltf)
    group = find_named(gltf, "Glass_Shards")
    if group < 0:
        raise SystemExit(f"{path.name}: no Glass_Shards group")
    old_shards = [c for c in gltf["nodes"][group].get("children", []) if gltf["nodes"][c].get("name", "").startswith("GlassShard")]
    shard_material = gltf["meshes"][gltf["nodes"][old_shards[0]]["mesh"]]["primitives"][0].get("material")
    intact = find_named(gltf, "Intact")
    pane_nodes = [n for n in subtree(gltf, intact) if "mesh" in gltf["nodes"][n] and "glass" in gltf["nodes"][n].get("name", "").lower()] if intact >= 0 else []
    if not pane_nodes:
        # The door ships without an Intact stage name in some exports.
        pane_nodes = [n for n in world if "mesh" in gltf["nodes"][n] and gltf["nodes"][n].get("name", "").lower() in ("doorglass", "glass")]
    to_group = np.linalg.inv(world[group])
    writer = Writer(gltf, binary)
    new_nodes = []
    pieces_per_pane = []
    for pane_index in pane_nodes:
        pane = Pane(gltf, binary, pane_index, world[pane_index])
        cells = voronoi_cells(pane.size[0], pane.size[1], seeds_for(pane.size[0], pane.size[1], rng), rng)
        areas = sorted(polygon_area(c) for c in cells)
        pieces_per_pane.append((gltf["nodes"][pane_index].get("name"), len(cells), round(pane.size[0], 2), round(pane.size[1], 2), round(areas[0] * 1e4), round(areas[-1] * 1e4)))
        for cell in cells:
            positions, normals, uvs, indices = shard_mesh(pane, cell, to_group)
            primitive = {
                "attributes": {
                    "POSITION": writer.add(positions, 5126, "VEC3", 34962, True),
                    "NORMAL": writer.add(normals, 5126, "VEC3", 34962),
                    "TEXCOORD_0": writer.add(uvs, 5126, "VEC2", 34962),
                },
                "indices": writer.add(indices, 5125, "SCALAR", 34963),
            }
            if shard_material is not None:
                primitive["material"] = shard_material
            gltf["meshes"].append({"name": f"GlassShard_{len(new_nodes):03d}", "primitives": [primitive]})
            gltf["nodes"].append({
                "name": f"GlassShard_{len(new_nodes):03d}",
                "mesh": len(gltf["meshes"]) - 1,
                "extras": {"fracture_stage": "Glass_Shards", "detachable_glass": True},
            })
            new_nodes.append(len(gltf["nodes"]) - 1)
    print(f"{path.name}: {len(old_shards)} grid shards -> {len(new_nodes)} irregular shards")
    for name, count, w, h, small, large in pieces_per_pane:
        print(f"  pane {name}: {w} x {h} m, {count} pieces, {small}-{large} cm^2")
    if check_only:
        return
    kept = [c for c in gltf["nodes"][group]["children"] if c not in old_shards]
    gltf["nodes"][group]["children"] = kept + new_nodes
    gltf, packed = compact(gltf, bytes(writer.binary))
    write_glb(path, gltf, packed)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for name, seed in TARGETS.items():
        fracture(MODELS / name, seed, args.check)
    return 0


if __name__ == "__main__":
    sys.exit(main())
