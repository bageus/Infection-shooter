# Blender fixes of the enemy source GLBs (models/objects/characters/enemy/<Name>.glb), 17.11.2026.
# Blender 5.3 as the bpy module (see /mnt/project-files/tools/blender/README.md):
#   /opt/bpy/bin/python tools/blender_fix_enemy_sources.py -- <Name> <in.glb> <out.glb>
#   python3 tools/deduplicate_model_textures.py --apply   # embedded atlases back to the shared files
# Blender re-encodes the wound image, so dedupe misses it: point that image back to
# Horde_Wound_BaseColor.png by hand (done for Hunger, Revenant, Titan, Colossus on 17.11.2026).
# 1. Seam strips (every part: faces whose UVs all sit on one white texel, which showed as white slits)
#    and Brute's shoulder cloth (UVs all 0,0, flat grey) take the UVs of the nearest real skin triangle
#    and the body material.
# 2. Titan: the head part had no neck cut; it is cut at the plane of the torso's neck cap and closed
#    with cut tissue like every other part.
# The source files were exported by an earlier tool with these defects; run this once on such a file.
import bpy, sys, bmesh
from mathutils.bvhtree import BVHTree
from mathutils import Vector
name, source, out = sys.argv[-3], sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=source)
DUMMY = [Vector((0.5, 0.004)), Vector((0.0, 0.0))]
def dummy(uv): return any((uv - d).length < 2e-3 for d in DUMMY)
total = 0
import numpy as np
albedo = next(n.image for m in bpy.data.materials if m.name.startswith(name + "_Textured") and m.node_tree
              for n in m.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image and 'BaseColor' in n.image.name)
AW, AH = albedo.size
APX = np.array(albedo.pixels[:], dtype=np.float32).reshape(AH, AW, 4)
def texel(uv): return APX[int((uv.y % 1.0) * (AH - 1)), int((uv.x % 1.0) * (AW - 1)), :3]
for o in [o for o in bpy.context.scene.objects if o.type == 'MESH']:
    mats = o.data.materials
    body_index = next(i for i, m in enumerate(mats) if m.name.startswith(name + '_Textured'))
    bm = bmesh.new(); bm.from_mesh(o.data); bm.faces.ensure_lookup_table()
    uvl = bm.loops.layers.uv[0]
    is_cut = lambda f: mats[f.material_index].name.startswith('Bloody_Cut')
    bad = [f for f in bm.faces if not is_cut(f) and (all(dummy(l[uvl].uv) for l in f.loops) or mats[f.material_index].name.endswith('Shoulder_Cloth'))]
    badset = set(bad)
    tris = []  # (verts co, uvs)
    for f in bm.faces:
        if f in badset or is_cut(f): continue
        loops = f.loops
        for k in range(1, len(loops) - 1):
            tris.append(((loops[0].vert.co.copy(), loops[k].vert.co.copy(), loops[k + 1].vert.co.copy()),
                         (loops[0][uvl].uv.copy(), loops[k][uvl].uv.copy(), loops[k + 1][uvl].uv.copy())))
    verts = [p for t in tris for p in t[0]]
    tree = BVHTree.FromPolygons(verts, [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(len(tris))])
    for f in bad:
        # Each corner takes the UV of the nearest real skin triangle's matching corner, so the face keeps
        # a non-degenerate UV (projecting every corner onto the skin collapsed wall faces to a point:
        # zero-area UVs break the tangents and render black).
        # nearest skin triangle whose texture there is not atlas padding (black) or the seam texel (white)
        centre = f.calc_center_median()
        candidates = sorted(tree.find_nearest_range(centre, 0.08), key=lambda hit: hit[3]) or [tree.find_nearest(centre)]
        index = candidates[0][2]
        for hit in candidates:
            c = texel(sum(tris[hit[2]][1], Vector((0.0, 0.0))) / 3.0)
            if 0.06 < c.max() and c.min() < 0.95:
                index = hit[2]
                break
        corners, uvs = tris[index]
        for k, l in enumerate(f.loops):
            nearest = min(range(3), key=lambda i: (corners[i] - l.vert.co).length) if k >= 3 else k
            l[uvl].uv = uvs[nearest]
        f.material_index = body_index
    total += len(bad)
    print(f"{o.name}: re-UV {len(bad)} faces")
    bm.to_mesh(o.data); bm.free()
    # drop now-unused material slots (cloth)
    used = {p.material_index for p in o.data.polygons}
    for i in reversed(range(len(mats))):
        if i not in used:
            o.active_material_index = i
            bpy.context.view_layer.objects.active = o
            o.data.materials.pop(index=i)
print("total", total)
if name == "Titan":
    import numpy as np
    torso = bpy.data.objects["Torso"]; head = bpy.data.objects["Head"]
    tm = torso.data.materials
    bm = bmesh.new(); bm.from_mesh(torso.data)
    # The torso's cut caps, grouped by position (the importer splits vertices at UV seams).
    capf = [f for f in bm.faces if tm[f.material_index].name.startswith('Bloody_Cut')]
    centre = lambda f: np.array(tuple(torso.matrix_world @ f.calc_center_median()))
    top = max((f for f in capf if abs(centre(f)[0]) < 0.12), key=lambda f: centre(f)[2])
    neck = [f for f in capf if np.linalg.norm(centre(f) - centre(top)) < 0.15]
    def pts(fs): return np.array([tuple(torso.matrix_world @ v.co) for f in fs for v in f.verts])
    P = pts(neck); c = P.mean(0)
    n = np.linalg.svd(P - c)[2][2]
    hc = np.array(tuple(head.matrix_world @ (sum((v.co for v in head.data.vertices), Vector()) / len(head.data.vertices))))
    if np.dot(hc - c, n) < 0: n = -n
    print("neck ring", len(neck), "edges, centre", c.round(3), "normal", n.round(3))
    bm.free()
    # cut the head at the torso's neck plane and close it with cut tissue like every other part
    cut_mat = next(m for m in tm if m.name.startswith('Bloody_Cut'))
    head.data.materials.append(cut_mat)
    cut_index = len(head.data.materials) - 1
    inv = head.matrix_world.inverted()
    co = inv @ Vector(c); no = (inv.to_3x3() @ Vector(n)).normalized()
    bm = bmesh.new(); bm.from_mesh(head.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)  # the importer split vertices at UV seams
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no, clear_inner=True)
    edges = [e for e in res['geom_cut'] if isinstance(e, bmesh.types.BMEdge)]
    before = len(bm.faces)
    filled = bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    caps = filled['faces']
    print("filled", len(caps), "faces from", len(edges), "edges")
    caps = bmesh.ops.triangulate(bm, faces=caps)['faces']
    uvl = bm.loops.layers.uv[0]
    axis_u = no.orthogonal().normalized(); axis_v = no.cross(axis_u)
    cv = [v for f in caps for v in f.verts]
    us = [(v.co - co).dot(axis_u) for v in cv]; vs = [(v.co - co).dot(axis_v) for v in cv]
    span = max(max(us) - min(us), max(vs) - min(vs), 1e-6)
    for f in caps:
        f.material_index = cut_index
        for l in f.loops:
            l[uvl].uv = (0.06 + 0.88 * ((l.vert.co - co).dot(axis_u) - min(us)) / span, 0.06 + 0.88 * ((l.vert.co - co).dot(axis_v) - min(vs)) / span)
    print("head cut:", len(edges), "rim edges,", len(caps), "cap faces")
    bm.to_mesh(head.data); bm.free()
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_tangents=True, export_vertex_color='ACTIVE', export_all_vertex_colors=True, export_yup=True, export_apply=False, export_image_format='AUTO')
