"""Flattens the Wardrobe costumes of the new enemy GLBs into small vertex-coloured meshes.

Run with the shared Blender (bpy wheel, see /mnt/project-files/tools/blender/README.md):
  /opt/bpy/bin/python tools/export_enemy_costumes.py -- <out_dir>
then build the game resources:
  godot --headless --path . --script res://tools/build_enemy_costumes.gd -- <out_dir>

Source: models/objects/characters/enemy/nwe/. Hunger and Brute hold a "Wardrobe" empty with one
child per costume (guard, hazmat, janitor, man, scientist), each holding one rigid mesh per body part
(<costume>_<Part>_details). Revenant keeps the same tree in Revenant_Accessories.glb. The meshes sit
in the same space as the body parts, so no re-fitting is needed.

Per costume the script writes <out_dir>/<Enemy>_<costume>.json with two meshes in Godot space (Y up):
  "solid"  one mesh, material base colour baked into vertex colours (linear), decimated
  "glass"  translucent parts (hazmat visor), kept whole
Colours become vertex colours so a costume costs one draw call instead of one per material.
"""
import json
import math
import os
import sys

import bpy
import bmesh

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SOURCE = os.path.join(ROOT, "models/objects/characters/enemy/nwe")
ENEMIES = {"Hunger": "Hunger.glb", "Brute": "Brute.glb", "Revenant": "Revenant_Accessories.glb"}
COSTUMES = ["guard", "hazmat", "janitor", "man", "scientist"]
# Triangle budget of a costume's opaque mesh; every material is decimated by the same ratio.
SOLID_BUDGET = 10000
# Materials below this many triangles are never decimated (badges, tags, patches).
SMALL_MATERIAL = 600
# Decimated cloth sinks into the body skin it hugs; push it out along its normals (metres).
INFLATE = 0.015


def _clean() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _material_info(material):
    node = material.node_tree.nodes.get("Principled BSDF")
    color = list(node.inputs["Base Color"].default_value)
    return color[:3], float(node.inputs["Alpha"].default_value)


def _split_by_material(obj):
    """One bmesh per material of `obj`, triangulated, in world space."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.transform(obj.matrix_world)
    result = {}
    for index, slot in enumerate(obj.material_slots):
        part = bm.copy()
        bmesh.ops.delete(part, geom=[f for f in part.faces if f.material_index != index], context="FACES")
        loose = [v for v in part.verts if not v.link_faces]
        bmesh.ops.delete(part, geom=loose, context="VERTS")
        if part.faces:
            result.setdefault(slot.material, []).append(part)
        else:
            part.free()
    bm.free()
    return result


def _decimated(bms, ratio):
    """Merge bmeshes into one object, decimate it, return (positions, normals, indices)."""
    mesh = bpy.data.meshes.new("part")
    merged = bmesh.new()
    for bm in bms:
        mesh_part = bpy.data.meshes.new("tmp")
        bm.to_mesh(mesh_part)
        merged.from_mesh(mesh_part)
        bpy.data.meshes.remove(mesh_part)
    merged.to_mesh(mesh)
    merged.free()
    obj = bpy.data.objects.new("part", mesh)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    if ratio < 0.999:
        mod = obj.modifiers.new("d", "DECIMATE")
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(55))
    # Weld the rigid per-part shells so neighbouring parts of one cloth share normals.
    mesh = obj.data
    positions, normals, indices, cache = [], [], [], {}
    corner_normals = mesh.corner_normals
    for poly in mesh.polygons:
        for loop_index in poly.loop_indices:
            vertex = mesh.loops[loop_index].vertex_index
            p = mesh.vertices[vertex].co
            n = corner_normals[loop_index].vector
            key = (round(p.x, 5), round(p.y, 5), round(p.z, 5), round(n.x, 2), round(n.y, 2), round(n.z, 2))
            if key not in cache:
                cache[key] = len(positions)
                # Blender Z-up to glTF/Godot Y-up: (x, y, z) -> (x, z, -y)
                p = p + n * INFLATE
                positions.append([p.x, p.z, -p.y])
                normals.append([n.x, n.z, -n.y])
            indices.append(cache[key])
        # glTF import in Blender reverses the winding; Godot wants counter-clockwise fronts.
        indices[-3], indices[-1] = indices[-1], indices[-3]
    bpy.data.objects.remove(obj)
    bpy.data.meshes.remove(mesh)
    return positions, normals, indices


def _export_group(name, group, out_dir, enemy):
    by_material = {}
    for obj in group:
        for material, bms in _split_by_material(obj).items():
            by_material.setdefault(material, []).extend(bms)
    solid, glass = [], []
    totals = {m: sum(len(bm.faces) for bm in bms) for m, bms in by_material.items()}
    large = sum(t for m, t in totals.items() if t >= SMALL_MATERIAL and _material_info(m)[1] >= 0.99)
    small = sum(t for m, t in totals.items() if t < SMALL_MATERIAL and _material_info(m)[1] >= 0.99)
    ratio = min(1.0, max(0.1, (SOLID_BUDGET - small) / max(large, 1)))
    for material, bms in by_material.items():
        color, alpha = _material_info(material)
        translucent = alpha < 0.99
        use_ratio = 1.0 if translucent or totals[material] < SMALL_MATERIAL else ratio
        positions, normals, indices = _decimated(bms, use_ratio)
        (glass if translucent else solid).append((color, alpha, positions, normals, indices))
    data = {}
    for key, entries in (("solid", solid), ("glass", glass)):
        out = {"positions": [], "normals": [], "colors": [], "indices": []}
        for color, alpha, positions, normals, indices in entries:
            base = len(out["positions"])
            out["positions"] += positions
            out["normals"] += normals
            out["colors"] += [color + [alpha]] * len(positions)
            out["indices"] += [base + i for i in indices]
        data[key] = out
    path = os.path.join(out_dir, "%s_%s.json" % (enemy, name))
    with open(path, "w") as handle:
        json.dump(data, handle, separators=(",", ":"))
    print("%s %s: solid %d tris, glass %d tris -> %s" % (enemy, name, len(data["solid"]["indices"]) // 3, len(data["glass"]["indices"]) // 3, path))


def main() -> None:
    out_dir = sys.argv[sys.argv.index("--") + 1]
    os.makedirs(out_dir, exist_ok=True)
    for enemy, file_name in ENEMIES.items():
        _clean()
        bpy.ops.import_scene.gltf(filepath=os.path.join(SOURCE, file_name))
        for costume in COSTUMES:
            group = [o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith(costume + "_")]
            if group:
                _export_group(costume, group, out_dir, enemy)
            else:
                print("%s has no %s costume" % (enemy, costume))


main()
