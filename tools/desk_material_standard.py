#!/usr/bin/env python3
"""Flat material standard for the desk and divider GLBs in models/objects/enviroments/08/.

Sibling of chair_material_standard.py (same GLB I/O, texture dropping and padding
rules). Materials are classified by name (a Blender ".001" style suffix is ignored):

    wood    (Oak_Veneer, Exposed_Wood)  base [0.42, 0.29, 0.18]    metallic 0.0  roughness 0.5
    frame   (Graphite_Frame)            base [0.035, 0.035, 0.04]  metallic 0.3  roughness 0.4
    fabric  (Fabric_Sand)               base [0.55, 0.5, 0.42]     metallic 0.0  roughness 0.9

Any other material name aborts without writing. The _fell variants are not listed.
Idempotent.

    python3 tools/desk_material_standard.py
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import chair_material_standard as base

ROOT = Path(__file__).resolve().parents[1] / "models/objects/enviroments/08"
FILES = [
    "08_office_desk_2.glb",
    "08_office_desk_4_coner.glb",
    "08_divider_full_H_desk.glb",
    "08_divider_full_U_desk.glb",
    "08_divider_full_H.glb",
    "08_divider_full_U.glb",
    "08_divider_black_high.glb",
    "08_divider_black_high_half.glb",
    "08_divider_black_low.glb",
    "08_divider_black_low_half.glb",
]
STANDARD = {
    "wood": ([0.42, 0.29, 0.18, 1.0], 0.0, 0.5),
    "frame": ([0.035, 0.035, 0.04, 1.0], 0.3, 0.4),
    "fabric": ([0.55, 0.5, 0.42, 1.0], 0.0, 0.9),
}
NAMES = {"Oak_Veneer": "wood", "Exposed_Wood": "wood", "Graphite_Frame": "frame", "Fabric_Sand": "fabric"}


def classify(name):
    return NAMES.get(re.sub(r"\.\d+$", "", name))


def apply_standard(doc):
    unknown = [m.get("name") for m in doc.get("materials", []) if not classify(m.get("name", ""))]
    if unknown:
        raise SystemExit("unclassified materials: %s" % unknown)
    for mat in doc.get("materials", []):
        base_color, metallic, rough = STANDARD[classify(mat["name"])]
        pbr = mat.setdefault("pbrMetallicRoughness", {})
        for key in ("baseColorTexture", "metallicRoughnessTexture"):
            pbr.pop(key, None)
        mat.pop("normalTexture", None)
        mat.pop("occlusionTexture", None)
        pbr["baseColorFactor"] = list(base_color)
        pbr["metallicFactor"] = metallic
        pbr["roughnessFactor"] = rough
    base.remap_textures(doc, base.texture_refs(doc))


def main():
    loaded = [(ROOT / n, *base.read_glb(ROOT / n)) for n in FILES]
    for _, doc, _ in loaded:
        apply_standard(doc)  # aborts before any write on an unknown material
    for path, doc, rest in loaded:
        base.write_glb(path, doc, rest)
        print("standardised", path.name, [m.get("name") for m in doc["materials"]])


if __name__ == "__main__":
    main()
