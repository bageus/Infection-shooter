#!/usr/bin/env python3
"""Offline quadric simplification for small prop GLBs, keeping the node tree and materials.

Each primitive is cut to about RATIO of its triangles (never below FLOOR triangles). Vertex
attributes of the kept vertices come from the nearest original vertex, so UVs, normals and
extra sets stay attached to the surface. Uses pyfqmr (pip install pyfqmr).

Usage: python3 tools/simplify_glb_props.py [--ratio 0.25] [--floor 120] file.glb ...
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

import numpy as np
import pyfqmr

COMPONENT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}


def read_glb(path: Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    if data[:4] != b"glTF":
        raise ValueError(f"{path}: not a GLB")
    off, doc, binary = 12, None, b""
    while off < len(data):
        length, kind = struct.unpack_from("<II", data, off)
        chunk = data[off + 8 : off + 8 + length]
        if kind == 0x4E4F534A:
            doc = json.loads(chunk.decode("utf-8"))
        elif kind == 0x004E4942:
            binary = chunk
        off += 8 + length
    if doc is None:
        raise ValueError(f"{path}: no JSON chunk")
    return doc, binary


def read_accessor(doc: dict, binary: bytes, index: int) -> np.ndarray:
    acc = doc["accessors"][index]
    dtype = np.dtype(COMPONENT[acc["componentType"]])
    ncomp = NCOMP[acc["type"]]
    count = acc["count"]
    if "bufferView" not in acc:
        return np.zeros((count, ncomp), dtype=dtype)
    view = doc["bufferViews"][acc["bufferView"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = view.get("byteStride", ncomp * dtype.itemsize)
    out = np.empty((count, ncomp), dtype=dtype)
    for i in range(count):
        out[i] = np.frombuffer(binary, dtype=dtype, count=ncomp, offset=start + i * stride)
    return out


class Builder:
    """Collects accessors into one tightly packed binary buffer."""

    def __init__(self) -> None:
        self.buffer = bytearray()
        self.views: list[dict] = []
        self.accessors: list[dict] = []

    def add(self, array: np.ndarray, acc_type: str, component: int, target: int | None = None, minmax: bool = False) -> int:
        pad = (-len(self.buffer)) % 4
        self.buffer.extend(b"\0" * pad)
        offset = len(self.buffer)
        raw = np.ascontiguousarray(array).tobytes()
        self.buffer.extend(raw)
        view: dict = {"buffer": 0, "byteOffset": offset, "byteLength": len(raw)}
        if target is not None:
            view["target"] = target
        self.views.append(view)
        acc: dict = {"bufferView": len(self.views) - 1, "componentType": component, "count": int(array.shape[0]), "type": acc_type}
        if minmax:
            acc["min"] = [float(x) for x in array.min(axis=0)]
            acc["max"] = [float(x) for x in array.max(axis=0)]
        self.accessors.append(acc)
        return len(self.accessors) - 1


COMP_OF = {np.dtype(np.float32): 5126, np.dtype(np.uint32): 5125, np.dtype(np.uint16): 5123, np.dtype(np.uint8): 5121}


def simplify_primitive(positions: np.ndarray, faces: np.ndarray, target_faces: int) -> tuple[np.ndarray, np.ndarray]:
    mesher = pyfqmr.Simplify()
    mesher.setMesh(positions.astype(np.float64), faces.astype(np.int32))
    mesher.simplify_mesh(target_count=target_faces, aggressiveness=7, preserve_border=False)
    verts, tris, _ = mesher.getMesh()
    return np.asarray(verts, dtype=np.float32), np.asarray(tris, dtype=np.int64)


def nearest_original(new_verts: np.ndarray, old_verts: np.ndarray) -> np.ndarray:
    # Brute force is fine for prop-sized meshes (a few thousand vertices).
    out = np.empty(len(new_verts), dtype=np.int64)
    for start in range(0, len(new_verts), 512):
        chunk = new_verts[start : start + 512]
        d = ((chunk[:, None, :] - old_verts[None, :, :]) ** 2).sum(axis=2)
        out[start : start + 512] = d.argmin(axis=1)
    return out


def process(path: Path, ratio: float, floor: int) -> tuple[int, int]:
    doc, binary = read_glb(path)
    builder = Builder()
    before = after = 0
    for mesh in doc["meshes"]:
        for prim in mesh["primitives"]:
            attrs = prim["attributes"]
            positions = read_accessor(doc, binary, attrs["POSITION"]).astype(np.float32)
            indices = read_accessor(doc, binary, prim["indices"]).reshape(-1, 3).astype(np.int64)
            faces_before = len(indices)
            before += faces_before
            target = max(floor, int(faces_before * ratio))
            streams = {name: read_accessor(doc, binary, idx) for name, idx in attrs.items()}
            if faces_before <= floor or target >= faces_before:
                new_positions, new_faces, source = positions, indices, np.arange(len(positions))
            else:
                new_positions, new_faces = simplify_primitive(positions, indices, target)
                source = nearest_original(new_positions, positions)
            after += len(new_faces)
            new_attrs = {}
            for name, stream in streams.items():
                data = new_positions if name == "POSITION" else stream[source]
                comp = COMP_OF[np.dtype(data.dtype)] if name != "POSITION" else 5126
                acc_type = {1: "SCALAR", 2: "VEC2", 3: "VEC3", 4: "VEC4"}[data.shape[1]] if data.ndim == 2 else "SCALAR"
                if name == "TANGENT" or data.dtype.kind == "i":
                    comp = COMP_OF[np.dtype(data.dtype)] if np.dtype(data.dtype) in COMP_OF else comp
                new_attrs[name] = builder.add(
                    data.astype(np.float32 if name != "JOINTS_0" else data.dtype),
                    acc_type,
                    5126 if name not in ("JOINTS_0",) else comp,
                    target=34962,
                    minmax=name == "POSITION",
                )
            flat = new_faces.astype(np.uint32).reshape(-1)
            prim["indices"] = builder.add(flat, "SCALAR", 5125, target=34963)
            prim["attributes"] = new_attrs
    # Keep non-geometry bytes out: accessors are rebuilt, so the old binary is dropped.
    doc["bufferViews"] = builder.views
    doc["accessors"] = builder.accessors
    doc["buffers"] = [{"byteLength": len(builder.buffer)}]
    binary_out = bytes(builder.buffer)
    json_bytes = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * ((-len(json_bytes)) % 4)
    binary_out += b"\0" * ((-len(binary_out)) % 4)
    total = 12 + 8 + len(json_bytes) + 8 + len(binary_out)
    out = bytearray(struct.pack("<III", 0x46546C67, 2, total))
    out += struct.pack("<II", len(json_bytes), 0x4E4F534A) + json_bytes
    out += struct.pack("<II", len(binary_out), 0x004E4942) + binary_out
    path.write_bytes(bytes(out))
    return before, after


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ratio", type=float, default=0.25)
    parser.add_argument("--floor", type=int, default=120)
    parser.add_argument("files", nargs="+", type=Path)
    args = parser.parse_args()
    for path in args.files:
        before, after = process(path, args.ratio, args.floor)
        print(f"{path}: {before} -> {after} triangles")
    return 0


if __name__ == "__main__":
    sys.exit(main())
