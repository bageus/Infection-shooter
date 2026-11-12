extends SceneTree
## Rasterises per-vertex geometry data of the enemy game meshes into UV space for
## tools/build_enemy_glow_masks.py: R = blister bump (how far a vertex sits above
## its Laplacian-smoothed neighbourhood), G = head region (top 0.28 m of the model).
## usage: godot --headless --path . -s tools/dump_enemy_uv_rasters.gd -- <out dir>
const NAMES := ["Brute", "Colossus", "Titan", "Horde", "Revenant", "Hunger"]
const SIZE := 1024
const SMOOTH_STEPS := 14
const BUMP_RANGE := 0.12 # metres of bump that map to full white

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	for n: String in NAMES:
		var mesh: ArrayMesh = load("res://models/objects/characters/enemy/game/%s_game.res" % n)
		var a := mesh.surface_get_arrays(0)
		_dump(n, out, a[Mesh.ARRAY_VERTEX], a[Mesh.ARRAY_NORMAL], a[Mesh.ARRAY_TEX_UV], a[Mesh.ARRAY_INDEX], mesh.get_aabb())
	quit()

func _dump(n: String, out: String, verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, idx: PackedInt32Array, box: AABB) -> void:
	var weld := {}
	var group := PackedInt32Array()
	group.resize(verts.size())
	for i in verts.size():
		var key := Vector3i((verts[i] * 2000.0).round())
		if not weld.has(key):
			weld[key] = weld.size()
		group[i] = weld[key]
	var count := weld.size()
	var pos := PackedVector3Array()
	pos.resize(count)
	var nor := PackedVector3Array()
	nor.resize(count)
	for i in verts.size():
		pos[group[i]] = verts[i]
		nor[group[i]] += normals[i]
	var neigh: Array[PackedInt32Array] = []
	neigh.resize(count)
	for t in idx.size() / 3:
		for k in 3:
			var g := group[idx[t * 3 + k]]
			neigh[g].append(group[idx[t * 3 + (k + 1) % 3]])
			neigh[g].append(group[idx[t * 3 + (k + 2) % 3]])
	var smooth := pos.duplicate()
	for step in SMOOTH_STEPS:
		var next := smooth.duplicate()
		for g in count:
			if neigh[g].is_empty():
				continue
			var sum := Vector3.ZERO
			for o in neigh[g]:
				sum += smooth[o]
			next[g] = smooth[g].lerp(sum / neigh[g].size(), 0.6)
		smooth = next
	var bump := PackedFloat32Array()
	bump.resize(verts.size())
	var head := PackedFloat32Array()
	head.resize(verts.size())
	for i in verts.size():
		var g := group[i]
		bump[i] = clampf((pos[g] - smooth[g]).dot(nor[g].normalized()) / BUMP_RANGE, 0.0, 1.0)
		head[i] = 1.0 if verts[i].y > box.end.y - 0.28 else 0.0
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for t in idx.size() / 3:
		var tri: Array[Vector2] = []
		var val: Array[Color] = []
		for k in 3:
			var vi := idx[t * 3 + k]
			tri.append(uvs[vi] * SIZE)
			val.append(Color(bump[vi], head[vi], 0.0))
		_fill(image, tri, val)
	image.save_png("%s/%s_raster.png" % [out, n])

func _fill(image: Image, p: Array[Vector2], c: Array[Color]) -> void:
	var lo := Vector2i(p[0].min(p[1]).min(p[2]).floor()).clamp(Vector2i.ZERO, Vector2i(SIZE - 1, SIZE - 1))
	var hi := Vector2i(p[0].max(p[1]).max(p[2]).ceil()).clamp(Vector2i.ZERO, Vector2i(SIZE - 1, SIZE - 1))
	var d := (p[1].y - p[2].y) * (p[0].x - p[2].x) + (p[2].x - p[1].x) * (p[0].y - p[2].y)
	if absf(d) < 1e-6:
		return
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var q := Vector2(x + 0.5, y + 0.5)
			var w0 := ((p[1].y - p[2].y) * (q.x - p[2].x) + (p[2].x - p[1].x) * (q.y - p[2].y)) / d
			var w1 := ((p[2].y - p[0].y) * (q.x - p[2].x) + (p[0].x - p[2].x) * (q.y - p[2].y)) / d
			var w2 := 1.0 - w0 - w1
			if w0 >= -0.02 and w1 >= -0.02 and w2 >= -0.02:
				image.set_pixel(x, y, c[0] * w0 + c[1] * w1 + c[2] * w2)
