# Skin weights of a whole enemy, computed in Blender (Vadim, 17.11.2026: one model, no cuts).
# Blender 5.3 as the bpy module (see /mnt/project-files/tools/blender/README.md):
#   /opt/bpy/bin/python tools/blender_enemy_weights.py -- <Name>
# Reads models/objects/characters/enemy/<Name>.glb (10 closed parts) and the joints of
# models/objects/characters/enemy/game/<Name>_rig.tscn (run tools/build_enemy_rigs.gd first), writes
# models/objects/characters/enemy/game/<Name>_weights.json. Run build_enemy_rigs.gd again afterwards:
# it skins the game mesh with these weights (enemy_rig_parts.gd humanoid_weights).
#
# The parts' skins are joined into one surface: cut tissue removed, the open rims of neighbouring
# parts bridged, so the body is one shell. Blender's bone heat (on a voxel remesh of it) then weights
# it as a single model, smoothly across the old cuts (per-part weights tore the hump on Colossus' back into shards
# whenever an arm rose). The output lists every vertex position (glTF space) with its 4 strongest
# bones; the game mesh looks its vertices up by position.
import bpy, bmesh, sys, re, json, os
from mathutils import Vector
from mathutils.kdtree import KDTree

name = sys.argv[-1]
HEAT_SCALE = 20.0
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "models", "objects", "characters", "enemy")
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, name + ".glb"))


def to_blender(p): return Vector((p[0], -p[2], p[1]))
def to_gltf(v): return [v.x, v.z, -v.y]


# --- joints from the rig (rests are translations only, so globals are sums of origins)
text = open(os.path.join(ROOT, "game", name + "_rig.tscn")).read()
names, parents, local = {}, {}, {}
for index, key, value in re.findall(r"bones/(\d+)/(name|parent|rest) = (.*)", text):
    index = int(index)
    if key == "name": names[index] = value.strip('"')
    elif key == "parent": parents[index] = int(value)
    else: local[index] = Vector([float(x) for x in value[value.index("(") + 1:value.rindex(")")].split(",")][9:12])
heads = {}
for index in sorted(names):
    heads[names[index]] = local[index] + (heads[names[parents[index]]] if parents[index] >= 0 else Vector())
bone_parent = {names[i]: (names[parents[i]] if parents[i] >= 0 else None) for i in names}
scale = (max(v.y for v in heads.values()) - heads["Root"].y) / 1.6
NEXT = {"Hips": "Spine", "Spine": "Chest", "Chest": "Neck", "Neck": "Head"}
for side in ("L_", "R_"):
    NEXT.update({side + "Shoulder": side + "UpperArm", side + "UpperArm": side + "Forearm", side + "Forearm": side + "Hand",
                 side + "Thigh": side + "Shin", side + "Shin": side + "Foot", side + "Foot": side + "Toe"})


def tail(bone):
    head = heads[bone]
    if bone in NEXT:
        return heads[NEXT[bone]]
    if bone == "Head":
        return head + Vector((0, 0.2 * scale, 0))
    if bone.endswith("Hand"):
        return head + (head - heads[bone[:2] + "Forearm"]).normalized() * 0.12 * scale
    if bone.endswith("Toe"):
        ahead = head - heads[bone[:2] + "Foot"]
        ahead.y = 0.0
        return head + ahead.normalized() * 0.1 * scale
    return head + Vector((0, 0.05 * scale, 0))


# --- one closed skin
parts = [o for o in bpy.context.scene.objects if o.type == 'MESH']
for o in parts:
    o.data.attributes.new("part", 'INT', 'POINT')
    for v in o.data.attributes["part"].data:
        v.value = parts.index(o)
bpy.ops.object.select_all(action='DESELECT')
for o in parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
# Bake the parts' offsets into the vertices: scaling about a part's origin would slide the body off the armature.
bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
mats = body.data.materials
bm = bmesh.new(); bm.from_mesh(body.data)
cut = [f for f in bm.faces if mats[f.material_index].name.startswith('Bloody_Cut')]
bmesh.ops.delete(bm, geom=cut, context='FACES')
bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
part_layer = bm.verts.layers.int["part"]
# open rims: loops of boundary edges, each within one part
loops, seen = [], set()
for e in bm.edges:
    if not e.is_boundary or e in seen:
        continue
    loop, stack = [], [e]
    while stack:
        x = stack.pop()
        if x in seen:
            continue
        seen.add(x); loop.append(x)
        for v in x.verts:
            stack += [y for y in v.link_edges if y.is_boundary and y not in seen]
    loops.append(loop)
def centre(loop): return sum((v.co for e in loop for v in e.verts), Vector()) / (2 * len(loop))
def part_of(loop): return loop[0].verts[0][part_layer]
bridged, used = 0, set()
for i, a in enumerate(loops):
    if i in used or len(a) < 6:
        continue
    best, best_d = None, 0.08 * scale
    for j, b in enumerate(loops):
        if j <= i or j in used or len(b) < 6 or part_of(b) == part_of(a):
            continue
        d = (centre(a) - centre(b)).length
        if d < best_d:
            best, best_d = j, d
    if best is None:
        continue
    try:
        bmesh.ops.bridge_loops(bm, edges=a + loops[best])
        used.update((i, best)); bridged += 1
    except Exception as error:  # a rim pair that will not bridge stays open; bone heat still weights it
        print("bridge failed:", part_of(a), part_of(loops[best]), error)
print(f"{name}: {len(loops)} rims, {bridged} joints bridged, {sum(1 for e in bm.edges if e.is_boundary)} open edges left")
bm.to_mesh(body.data); bm.free()

# --- armature from the game rig, bone heat
bpy.ops.object.armature_add(enter_editmode=True)
rig = bpy.context.view_layer.objects.active
edit = rig.data.edit_bones
edit.remove(edit[0])
for bone in heads:
    b = edit.new(bone)
    b.head = to_blender(heads[bone]); b.tail = to_blender(tail(bone))
    b.use_deform = bone != "Root"
for bone, parent in bone_parent.items():
    if parent:
        edit[bone].parent = edit[parent]
bpy.ops.object.mode_set(mode='OBJECT')
# Bone heat fails on small meshes (these bodies are 1.9 units tall): work 20 times larger.
for o in (body, rig):
    o.scale = (HEAT_SCALE,) * 3
bpy.ops.object.select_all(action='DESELECT')
body.select_set(True); rig.select_set(True)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
# Bone heat needs one clean closed shell; torn clothes, flaps and inner shells make it fail
# (Brute, Titan). It runs on a voxel remesh of the body, whose weights then move onto the real
# vertices from the nearest point of the proxy surface.
bpy.ops.object.select_all(action='DESELECT')
body.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.duplicate()
proxy = bpy.context.view_layer.objects.active
remesh = proxy.modifiers.new("remesh", 'REMESH')
remesh.mode = 'VOXEL'
remesh.voxel_size = 0.015 * scale * HEAT_SCALE
bpy.ops.object.modifier_apply(modifier=remesh.name)
# keep the outer shell only: inner shells of the remesh leave bone heat without a solution
pm = bmesh.new(); pm.from_mesh(proxy.data)
shells, seen = [], set()
for f in pm.faces:
    if f in seen:
        continue
    shell, stack = [], [f]
    seen.add(f)
    while stack:
        g = stack.pop(); shell.append(g)
        for e in g.edges:
            for h in e.link_faces:
                if h not in seen:
                    seen.add(h); stack.append(h)
    shells.append(shell)
shells.sort(key=len, reverse=True)
bmesh.ops.delete(pm, geom=[f for shell in shells[1:] for f in shell], context='FACES')
pm.to_mesh(proxy.data); pm.free()
bpy.ops.object.select_all(action='DESELECT')
proxy.select_set(True); rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type='ARMATURE_AUTO')
for g in proxy.vertex_groups:
    body.vertex_groups.new(name=g.name)
transfer = body.modifiers.new("weights", 'DATA_TRANSFER')
transfer.object = proxy
transfer.use_vert_data = True
transfer.data_types_verts = {'VGROUP_WEIGHTS'}
transfer.vert_mapping = 'POLYINTERP_NEAREST'
transfer.layers_vgroup_select_src = 'ALL'
transfer.layers_vgroup_select_dst = 'NAME'
bpy.ops.object.select_all(action='DESELECT')
body.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.modifier_apply(modifier=transfer.name)
print(f"{name}: heat on a {len(proxy.data.vertices)}-vertex remesh (outer of {len(shells)} shells)")

# --- every vertex with its 4 strongest bones; vertices bone heat missed take the nearest weighted one
me = body.data
groups = {g.index: g.name for g in body.vertex_groups}
world = body.matrix_world
rows = []
for v in me.vertices:
    pairs = sorted(((g.weight, groups[g.group]) for g in v.groups if g.weight > 1e-4), reverse=True)[:4]
    rows.append((world @ v.co / HEAT_SCALE, pairs))
weighted = [i for i, r in enumerate(rows) if r[1]]
tree = KDTree(len(weighted))
for k, i in enumerate(weighted):
    tree.insert(rows[i][0], k)
tree.balance()
missing = 0
bones_out = [b for b in heads if b != "Root"]
positions, bone_ids, weights = [], [], []
for co, pairs in rows:
    if not pairs:
        pairs = rows[weighted[tree.find(co)[1]]][1]; missing += 1
    total = sum(w for w, _ in pairs)
    pairs = pairs + [(0.0, pairs[0][1])] * (4 - len(pairs))
    positions += [round(x, 5) for x in to_gltf(co)]
    bone_ids += [bones_out.index(b) for _, b in pairs]
    weights += [round(w / total, 4) for w, _ in pairs]
print(f"{name}: {len(rows)} vertices, {missing} without heat weights took their neighbour's")
json.dump({"bones": bones_out, "positions": positions, "bones_of": bone_ids, "weights": weights},
          open(os.path.join(ROOT, "game", name + "_weights.json"), "w"), separators=(",", ":"))
