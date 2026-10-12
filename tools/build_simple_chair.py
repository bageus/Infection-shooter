#!/usr/bin/env python3
"""Rebuilds models/objects/enviroments/06/06_simple_chair(.glb|_fell.glb).

The previous export had a second, off-centre cushion mesh inside the seat, 576
vertex legs and a dark, unreadable fully-metallic steel material. This script
keeps the node tree, node transforms, destruction extras, material slots and the
overall dimensions, and regenerates clean geometry: rounded seat + cushion and
backrest with smooth normals, and light 12-sided tapered legs with an unstretched
brushed-steel UV mapping.

    python3 tools/build_simple_chair.py
"""
import json
import struct
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1] / "models/objects/enviroments/06"
UPRIGHT = ROOT / "06_simple_chair.glb"
FELL = ROOT / "06_simple_chair_fell.glb"
# Brushed steel lives in the top-right quarter of the chair atlas.
STEEL_UV = (0.51, 0.01, 0.99, 0.49)
LEATHER_UV = (0.01, 0.01, 0.49, 0.49)
LEG_SIDES = 12


def load(path):
    data = path.read_bytes()
    jlen = struct.unpack("<I", data[12:16])[0]
    return json.loads(data[20:20 + jlen]), data


def rounded_box(center, half, radius, uv_rect):
    """Rounded cuboid from an inflated cube grid; returns pos, normal, uv, idx."""
    h = np.array(half, float)
    r = float(radius)
    axis_vals = []
    for a in range(3):
        inner = h[a] - r
        axis_vals.append([-h[a], -inner - 0.4 * r, -inner, inner, inner + 0.4 * r, h[a]])
    pos, nor, uv, idx = [], [], [], []
    n = 6
    for axis in range(3):
        u_ax, v_ax = [a for a in range(3) if a != axis]
        for sign in (-1.0, 1.0):
            base = len(pos)
            for iu in range(n):
                for iv in range(n):
                    q = np.zeros(3)
                    q[axis] = sign * h[axis]
                    q[u_ax] = axis_vals[u_ax][iu]
                    q[v_ax] = axis_vals[v_ax][iv]
                    inner = np.clip(q, -(h - r), h - r)
                    d = q - inner
                    nrm = d / np.linalg.norm(d)
                    pos.append(np.array(center) + inner + r * nrm)
                    nor.append(nrm)
                    # Box projection scaled to world size, no stretching.
                    p = pos[-1] - np.array(center)
                    uu = (p[u_ax] / (2 * h[u_ax]) + 0.5)
                    vv = (p[v_ax] / (2 * h[v_ax]) + 0.5)
                    uv.append((uv_rect[0] + uu * (uv_rect[2] - uv_rect[0]),
                               uv_rect[1] + vv * (uv_rect[3] - uv_rect[1])))
            for iu in range(n - 1):
                for iv in range(n - 1):
                    a0 = base + iu * n + iv
                    a1 = a0 + 1
                    b0 = a0 + n
                    b1 = b0 + 1
                    for tri in ((a0, a1, b1), (a0, b1, b0)):
                        p0, p1, p2 = (pos[t] for t in tri)
                        face = np.cross(p1 - p0, p2 - p0)
                        flat = (nor[tri[0]] + nor[tri[1]] + nor[tri[2]])
                        idx.extend(tri if face @ flat >= 0 else (tri[0], tri[2], tri[1]))
    return np.array(pos), np.array(nor), np.array(uv), np.array(idx, dtype=np.uint32)


def leg(center, top_y, bottom_y, r_top, r_bottom):
    """Tapered cylinder, axis Y, UV: length along U, circumference along V."""
    pos, nor, uv, idx = [], [], [], []
    slope = (r_top - r_bottom) / (top_y - bottom_y)
    length = top_y - bottom_y
    circ = 2 * np.pi * (r_top + r_bottom) / 2
    scale = (STEEL_UV[2] - STEEL_UV[0]) / 1.2  # uv per metre, atlas tile ~1.2 m
    for ring, (y, rad) in enumerate(((top_y, r_top), (bottom_y, r_bottom))):
        for k in range(LEG_SIDES + 1):
            a = 2 * np.pi * k / LEG_SIDES
            c, s = np.cos(a), np.sin(a)
            pos.append(np.array(center) + [rad * c, y, rad * s])
            n = np.array([c, slope, s])
            nor.append(n / np.linalg.norm(n))
            uv.append((STEEL_UV[0] + 0.01 + ring * length * scale,
                       STEEL_UV[1] + 0.01 + k / LEG_SIDES * circ * scale))
    for k in range(LEG_SIDES):
        a0, a1 = k, k + 1
        b0, b1 = a0 + LEG_SIDES + 1, a1 + LEG_SIDES + 1
        idx.extend((a0, b0, b1, a0, b1, a1))
    # Foot cap.
    cap = len(pos)
    pos.append(np.array(center) + [0, bottom_y, 0])
    nor.append(np.array([0.0, -1.0, 0.0]))
    uv.append((STEEL_UV[0] + 0.1, STEEL_UV[1] + 0.1))
    for k in range(LEG_SIDES):
        pos.append(np.array(center) + [r_bottom * np.cos(2 * np.pi * k / LEG_SIDES), bottom_y,
                                       r_bottom * np.sin(2 * np.pi * k / LEG_SIDES)])
        nor.append(np.array([0.0, -1.0, 0.0]))
        uv.append((STEEL_UV[0] + 0.1, STEEL_UV[1] + 0.1))
    for k in range(LEG_SIDES):
        idx.extend((cap, cap + 1 + (k + 1) % LEG_SIDES, cap + 1 + k))
    return np.array(pos), np.array(nor), np.array(uv), np.array(idx, dtype=np.uint32)


def tangents(pos, nor, uv, idx):
    tan = np.zeros((len(pos), 3))
    for i in range(0, len(idx), 3):
        a, b, c = idx[i:i + 3]
        e1, e2 = pos[b] - pos[a], pos[c] - pos[a]
        d1, d2 = uv[b] - uv[a], uv[c] - uv[a]
        det = d1[0] * d2[1] - d2[0] * d1[1]
        if abs(det) < 1e-12:
            continue
        t = (e1 * d2[1] - e2 * d1[1]) / det
        for v in (a, b, c):
            tan[v] += t
    out = np.zeros((len(pos), 4))
    for i in range(len(pos)):
        t = tan[i] - nor[i] * (nor[i] @ tan[i])
        ln = np.linalg.norm(t)
        t = t / ln if ln > 1e-9 else np.cross(nor[i], [0, 1, 0] if abs(nor[i][1]) < .9 else [1, 0, 0])
        out[i, :3] = t / np.linalg.norm(t)
        out[i, 3] = 1.0
    return out


def merge(parts):
    pos, nor, uv, idx, off = [], [], [], [], 0
    for p, n, u, i in parts:
        pos.append(p); nor.append(n); uv.append(u); idx.append(i + off)
        off += len(p)
    return np.vstack(pos), np.vstack(nor), np.vstack(uv), np.concatenate(idx)


def build(path, rotation):
    j, _ = load(path)
    # Geometry is authored for the upright chair; the fell variant applies the
    # same fixed rotation the original export used. `world` offsets are the
    # upright node translations.
    up = {n["name"]: np.array(n["translation"]) for n in load(UPRIGHT)[0]["nodes"]}
    chair_c = up["Chair"]

    parts = {}
    # seat: frame slab + cushion, local to the seat node
    base = rounded_box([0, -0.025, 0], [0.2652, 0.0370, 0.2481], 0.028, LEATHER_UV)
    cush = rounded_box([0, 0.0300, 0.0], [0.2370, 0.0300, 0.2230], 0.026, LEATHER_UV)
    parts["seat"] = {1: base, 2: cush}
    parts["back"] = {1: rounded_box([0, 0, 0], [0.2455, 0.2304, 0.0466], 0.032, LEATHER_UV)}
    for name in ("leg_left_front", "leg_left_rear", "leg_right_front", "leg_right_rear"):
        parts[name] = {0: leg([0, 0, 0], 0.2675, -0.2675, 0.030, 0.022)}

    def shifted(prim, delta):
        p, n, u, i = prim
        return p + delta, n, u, i

    intact = {1: [], 2: [], 0: []}
    for name, mats in parts.items():
        delta = up[name] - chair_c
        for mat, prim in mats.items():
            intact[mat].append(shifted(prim, delta))
    parts["Chair"] = {m: merge(v) for m, v in intact.items()}
    rot = np.eye(3) if rotation is None else rotation
    meshes = []
    chunks = []
    accessors, views = [], []

    def add(arr, comp, typ, target, mins=None):
        raw = np.ascontiguousarray(arr).tobytes()
        pad = (-len(raw)) % 4
        views.append({"buffer": 0, "byteOffset": sum(len(c) for c in chunks), "byteLength": len(raw), "target": target})
        chunks.append(raw + b"\0" * pad)
        acc = {"bufferView": len(views) - 1, "componentType": comp, "count": len(arr), "type": typ}
        if mins:
            acc["min"] = np.min(arr, 0).astype(float).tolist()
            acc["max"] = np.max(arr, 0).astype(float).tolist()
        accessors.append(acc)
        return len(accessors) - 1

    for mesh in j["meshes"]:
        prims = []
        for old in mesh["primitives"]:
            mat = old["material"]
            pos, nor, uv, idx = parts[mesh["name"]][mat]
            pos, nor = pos @ rot.T, nor @ rot.T
            tan = tangents(pos, nor, uv, idx)
            prims.append({
                "attributes": {
                    "NORMAL": add(nor.astype("<f4"), 5126, "VEC3", 34962, True),
                    "POSITION": add(pos.astype("<f4"), 5126, "VEC3", 34962, True),
                    "TANGENT": add(tan.astype("<f4"), 5126, "VEC4", 34962, True),
                    "TEXCOORD_0": add(uv.astype("<f4"), 5126, "VEC2", 34962, True),
                },
                "indices": add(idx.astype("<u4"), 5125, "SCALAR", 34963),
                "material": mat, "mode": 4,
            })
        mesh["primitives"] = prims
    # Brushed steel: readable instead of a fully mirror-metal black.
    for m in j["materials"]:
        if m.get("name") == "Brushed_Steel":
            m["pbrMetallicRoughness"]["metallicFactor"] = 0.6
            m["pbrMetallicRoughness"]["roughnessFactor"] = 0.55
            m["pbrMetallicRoughness"]["baseColorFactor"] = [0.5, 0.5, 0.53, 1]
    j["accessors"], j["bufferViews"] = accessors, views
    blob = b"".join(chunks)
    j["buffers"] = [{"byteLength": len(blob)}]
    j["asset"]["generator"] = "tools/build_simple_chair.py"
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * ((-len(js)) % 4)
    total = 12 + 8 + len(js) + 8 + len(blob)
    return (b"glTF" + struct.pack("<II", 2, total) + struct.pack("<I", len(js)) + b"JSON" + js
            + struct.pack("<I", len(blob)) + b"BIN\0" + blob)


def fell_rotation():
    """Fixed rotation mapping the upright part meshes to the fell variant."""
    ju, du = load(UPRIGHT)
    jf, df = load(FELL)
    def pos(j, data, mesh):
        jl = struct.unpack("<I", data[12:16])[0]
        base = 28 + jl
        a = j["accessors"][j["meshes"][mesh]["primitives"][0]["attributes"]["POSITION"]]
        bv = j["bufferViews"][a["bufferView"]]
        return np.frombuffer(data, "<f4", a["count"] * 3, base + bv["byteOffset"]).reshape(-1, 3).astype(float)
    A, B = pos(ju, du, 1), pos(jf, df, 1)
    ca, cb = A.mean(0), B.mean(0)
    U, _, Vt = np.linalg.svd((A - ca).T @ (B - cb))
    return (U @ Vt).T


if __name__ == "__main__":
    rot = fell_rotation()  # needs the ORIGINAL files; computed before writing
    outputs = {UPRIGHT: build(UPRIGHT, None), FELL: build(FELL, rot)}
    for p, b in outputs.items():
        p.write_bytes(b)
        print("wrote", p.relative_to(ROOT.parents[3]), len(b), "bytes")
