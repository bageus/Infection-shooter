#!/usr/bin/env python3
"""One shared material standard for the chair GLBs in models/objects/enviroments/06/.

Based on the simple chair, whose flat dark leather reads well in game. Every
material is classified by name and rewritten to the values of its class:

    leather (Leather)        base [0.012, 0.012, 0.014]  metallic 0.0  roughness 0.22
    polymer (Polymer)        base [0.035, 0.035, 0.04]   metallic 0.0  roughness 0.45
    metal   (Steel / Metal)  base [0.5, 0.5, 0.53]       metallic 0.6  roughness 0.55

All classes are flat: baseColor, normal, metallicRoughness and occlusion texture
references are removed. Images, textures and samplers that nothing references
any more are dropped and the remaining indices are remapped. Meshes, nodes,
transforms, extras, UVs and accessors are not touched. The JSON chunk is
rewritten in place (space padded to 4 bytes) and the binary chunk is kept.
The script is idempotent.

    python3 tools/chair_material_standard.py
"""
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "models/objects/enviroments/06"
CHAIRS = [
    "06_simple_chair.glb",
    "06_simple_chair_fell.glb",
    "06_conference_chair.glb",
    "06_office_chair.glb",
]
STANDARD = {
    "leather": ([0.012, 0.012, 0.014, 1.0], 0.0, 0.22),
    "polymer": ([0.035, 0.035, 0.04, 1.0], 0.0, 0.45),
    "metal": ([0.5, 0.5, 0.53, 1.0], 0.6, 0.55),
}
# (key, name substrings) in priority order.
CLASSES = [("leather", ("Leather",)), ("polymer", ("Polymer",)), ("metal", ("Steel", "Metal"))]


def classify(name):
    for key, words in CLASSES:
        if any(w in name for w in words):
            return key
    return None


def read_glb(path):
    data = path.read_bytes()
    jlen = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(data[20:20 + jlen])
    return doc, data[20 + jlen:]


def write_glb(path, doc, rest):
    blob = json.dumps(doc, separators=(",", ":")).encode()
    blob += b" " * (-len(blob) % 4)
    total = 12 + 8 + len(blob) + len(rest)
    head = b"glTF" + struct.pack("<II", 2, total) + struct.pack("<I", len(blob)) + b"JSON"
    path.write_bytes(head + blob + rest)


def flatten(mat, cls):
    base, metallic, rough = STANDARD[cls]
    pbr = mat.setdefault("pbrMetallicRoughness", {})
    for key in ("baseColorTexture", "metallicRoughnessTexture"):
        pbr.pop(key, None)
    mat.pop("normalTexture", None)
    mat.pop("occlusionTexture", None)
    pbr["baseColorFactor"] = list(base)
    pbr["metallicFactor"] = metallic
    pbr["roughnessFactor"] = rough


def texture_refs(doc):
    """Texture indices still referenced by any material."""
    used = set()
    for mat in doc.get("materials", []):
        slots = [mat.get("normalTexture"), mat.get("occlusionTexture"), mat.get("emissiveTexture")]
        pbr = mat.get("pbrMetallicRoughness", {})
        slots += [pbr.get("baseColorTexture"), pbr.get("metallicRoughnessTexture")]
        used.update(s["index"] for s in slots if s)
    return used


def remap_textures(doc, keep):
    """Drop unreferenced textures, then unreferenced images and samplers."""
    textures = doc.get("textures", [])
    new_index = {}
    kept = []
    for i, tex in enumerate(textures):
        if i in keep:
            new_index[i] = len(kept)
            kept.append(tex)
    for mat in doc.get("materials", []):
        pbr = mat.get("pbrMetallicRoughness", {})
        for holder in (mat, pbr):
            for key, val in holder.items():
                if key.endswith("Texture") and isinstance(val, dict):
                    val["index"] = new_index[val["index"]]
    for field, ref in (("images", "source"), ("samplers", "sampler")):
        if field not in doc:
            continue
        used = sorted({t[ref] for t in kept if ref in t})
        order = {old: new for new, old in enumerate(used)}
        for t in kept:
            if ref in t:
                t[ref] = order[t[ref]]
        doc[field] = [doc[field][i] for i in used]
        if not doc[field]:
            del doc[field]
    if kept:
        doc["textures"] = kept
    else:
        doc.pop("textures", None)


def apply_standard(doc):
    for mat in doc.get("materials", []):
        cls = classify(mat.get("name", ""))
        if cls:
            flatten(mat, cls)
        else:
            print("  unclassified material left alone:", mat.get("name"))
    remap_textures(doc, texture_refs(doc))


def main():
    for name in CHAIRS:
        path = ROOT / name
        doc, rest = read_glb(path)
        apply_standard(doc)
        write_glb(path, doc, rest)
        print("standardised", name, [m.get("name") for m in doc.get("materials", [])])


if __name__ == "__main__":
    main()
