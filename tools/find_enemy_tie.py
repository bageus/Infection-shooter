"""Finds the necktie of the enemy bodies in UV space, for the "no_tie" skin.

Run with the shared Blender (bpy wheel, see /mnt/project-files/tools/blender/README.md):
  /opt/bpy/bin/python tools/find_enemy_tie.py -- <out_dir>
then cut it out of the rig meshes:
  godot --headless --path . --script res://tools/build_no_tie_meshes.gd -- <out_dir>
The tie is a few small loose parts of the Torso mesh (dark, on the chest centre line, facing front).
Their UV triangles are written (white on black, a few pixels grown) to <out_dir>/<Enemy>_tie_mask.png.
"""
import os
import sys

import bpy
import bmesh
import mathutils
import numpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
NWE = os.path.join(ROOT, "models/objects/characters/enemy/nwe")
GAME = os.path.join(ROOT, "models/objects/characters/enemy/game")
OUT = sys.argv[sys.argv.index("--") + 1]
os.makedirs(OUT, exist_ok=True)
ENEMIES = {"Hunger": "Hunger.glb", "Brute": "Brute.glb", "Revenant": "Revenant_Shared.glb"}
DARK = 0.25
CENTER = 0.1
MIN_Z = 0.15
# The tie hangs on the chest front (Blender -Y), not on the collar's inner side.
FRONT_Y = -0.05
FACE_DARK = 0.3
FACE_CENTER = 0.05
FACE_MIN_Z = 0.2


def _islands(bm):
    seen, result = set(), []
    for face in bm.faces:
        if face.index in seen:
            continue
        stack, island = [face], []
        seen.add(face.index)
        while stack:
            current = stack.pop()
            island.append(current)
            for edge in current.edges:
                for other in edge.link_faces:
                    if other.index not in seen:
                        seen.add(other.index)
                        stack.append(other)
        result.append(island)
    return result


def _paint(enemy, glb):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(NWE, glb))
    obj = bpy.data.objects["Torso"]
    image = bpy.data.images.load(os.path.join(GAME, enemy + "_albedo.jpg"))
    width, height = image.size
    pixels = numpy.empty(width * height * 4, dtype=numpy.float32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape(height, width, 4)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.normal_update()
    uv = bm.loops.layers.uv.active

    def luminance(face):
        u = sum(l[uv].uv.x for l in face.loops) / len(face.loops)
        v = sum(l[uv].uv.y for l in face.loops) / len(face.loops)
        return float(pixels[min(height - 1, int(v * height)), min(width - 1, int(u * width)), :3].mean())

    tie = []
    for island in _islands(bm):
        if len(island) < 3:
            continue
        lum = sum(luminance(f) for f in island) / len(island)
        centre = sum((obj.matrix_world @ f.calc_center_median() for f in island), mathutils.Vector()) / len(island)
        if lum < DARK and abs(centre.x) < CENTER and centre.z > MIN_Z and centre.y < FRONT_Y:
            tie.append(island)
    # Where the tie shares an island with the shirt, single dark faces on the centre line count too.
    taken = {f.index for island in tie for f in island}
    for face in bm.faces:
        centre = obj.matrix_world @ face.calc_center_median()
        if face.index not in taken and luminance(face) < FACE_DARK and abs(centre.x) < FACE_CENTER and centre.z > FACE_MIN_Z and centre.y < FRONT_Y:
            tie.append([face])

    mask = numpy.zeros((height, width), dtype=bool)
    for island in tie:
        for f in island:
            pts = numpy.array([[l[uv].uv.x * width, l[uv].uv.y * height] for l in f.loops])
            for k in range(1, len(pts) - 1):
                _fill(mask, pts[0], pts[k], pts[k + 1])
    # Grow a few pixels so the texture filtering never picks up the old tie colour.
    for _ in range(4):
        grown = mask.copy()
        grown[1:] |= mask[:-1]
        grown[:-1] |= mask[1:]
        grown[:, 1:] |= mask[:, :-1]
        grown[:, :-1] |= mask[:, 1:]
        mask = grown
    out = bpy.data.images.new(enemy, width, height)
    pixels[..., :3] = mask[..., None].astype(numpy.float32)
    pixels[..., 3] = 1.0
    out.pixels.foreach_set(pixels.reshape(-1))
    out.filepath_raw = os.path.join(OUT, enemy + "_tie_mask.png")
    out.file_format = "PNG"
    out.save()
    print("%s: %d tie islands, %d pixels" % (enemy, len(tie), int(mask.sum())))


def _fill(mask, a, b, c):
    xs, ys = [a[0], b[0], c[0]], [a[1], b[1], c[1]]
    x0, x1 = max(int(min(xs)), 0), min(int(max(xs)) + 1, mask.shape[1] - 1)
    y0, y1 = max(int(min(ys)), 0), min(int(max(ys)) + 1, mask.shape[0] - 1)
    gx, gy = numpy.meshgrid(numpy.arange(x0, x1 + 1) + 0.5, numpy.arange(y0, y1 + 1) + 0.5)
    det = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
    if abs(det) < 1e-9:
        return
    w1 = ((b[1] - c[1]) * (gx - c[0]) + (c[0] - b[0]) * (gy - c[1])) / det
    w2 = ((c[1] - a[1]) * (gx - c[0]) + (a[0] - c[0]) * (gy - c[1])) / det
    inside = (w1 >= -0.01) & (w2 >= -0.01) & (1 - w1 - w2 >= -0.01)
    mask[y0:y1 + 1, x0:x1 + 1] |= inside


for name, file_name in ENEMIES.items():
    _paint(name, file_name)
