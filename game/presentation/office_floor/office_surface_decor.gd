extends RefCounted
## Office surface dressing (surface_decor_v1): the conference table finish,
## a printed document on the visible top sheet of loose paper and 0-3 sticky
## notes along monitor edges. Pure presentation; nothing here is persisted.

const DOCUMENT_ATLAS := preload("res://models/objects/textures/paper/Six transparent office document overlays.png")
const STICKER_ATLAS := preload("res://models/objects/textures/display/Eight-note colorful office sticker atlas.png")
const TABLE_WOOD := preload("res://models/objects/textures/table/conference_table_chocolate_wood.png")
const TABLE_GRAPHITE := preload("res://models/objects/textures/table/conference_table_graphite.png")

const TABLE_MODELS: Array[String] = ["07_table_longest.glb"]
# Source material name -> finish. The white top becomes chocolate wood, the frame graphite.
const TABLE_FINISH := {"Modern_Warm_White": "wood", "Modern_Graphite": "graphite"}
# Flat sheets whose top face is seen from the gameplay camera.
const PAPER_MODELS: Array[String] = ["09_paper_stack.glb", "09_paper_stray.glb", "09_office_files_a.glb",
	"09_office_files_a_2.glb", "09_office_file_single.glb"]
# The overlay atlas is not a uniform grid; each document occupies its own pixel rectangle.
const DOCUMENT_RECTS: Array[Rect2] = [Rect2(140, 30, 435, 516), Rect2(590, 30, 440, 516), Rect2(1040, 30, 490, 516),
	Rect2(135, 546, 450, 474), Rect2(595, 546, 473, 474), Rect2(1072, 546, 458, 474)]
const STICKER_FRAMES := Vector2i(4, 2)
const MAX_STICKERS := 3
# Candidate sticker centres in half-screen units with the outward edge direction.
const STICKER_SLOTS: Array[Vector4] = [Vector4(-0.6, 1, 0, 1), Vector4(0, 1, 0, 1), Vector4(0.6, 1, 0, 1),
	Vector4(-1, 0.4, -1, 0), Vector4(-1, -0.35, -1, 0), Vector4(1, 0.4, 1, 0), Vector4(1, -0.35, 1, 0),
	Vector4(-0.55, -1, 0, -1), Vector4(0.55, -1, 0, -1)]
const PAPER_LIFT := 0.0015

static var _materials := {}


static func apply(visual: Node3D, model_path: String, display: Node3D = null, display_seed: int = 0) -> void:
	if visual == null:
		return
	var file := model_path.get_file()
	if file in TABLE_MODELS:
		finish_table(visual)
	elif file in PAPER_MODELS:
		print_document(visual, randi())
	elif "monitor" in file and is_instance_valid(display):
		var profiles: Array = []
		for screen: Dictionary in display.get("screens"):
			profiles.append(screen["profile"])
		add_stickers(visual, profiles, display_seed)


static func finish_table(visual: Node3D) -> int:
	var changed := 0
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface)
			if source != null and TABLE_FINISH.has(source.resource_name):
				mesh.set_surface_override_material(surface, material(str(TABLE_FINISH[source.resource_name])))
				changed += 1
	return changed


## Lays one random document over the highest sheet, draped over its real surface.
static func print_document(visual: Node3D, seed_value: int) -> MeshInstance3D:
	var to_visual := visual.global_transform.affine_inverse()
	var faces := PackedVector3Array()
	var top_height := -INF
	var top_points := PackedVector3Array()
	var top_basis := Basis()
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var transform := to_visual * mesh.global_transform
		if absf(transform.basis.determinant()) < 0.000000000001:
			continue # Hidden zero-scale damage stages.
		var source := mesh.mesh.get_faces()
		var points := PackedVector3Array()
		for i in range(0, source.size() - 2, 3):
			var a := transform * source[i]
			var b := transform * source[i + 1]
			var c := transform * source[i + 2]
			var normal := (b - a).cross(c - a)
			if normal.length_squared() < 0.0000000001 or absf(normal.normalized().y) < 0.5:
				continue
			faces.append_array([a, b, c])
			points.append_array([a, b, c])
		for point in points:
			if point.y > top_height:
				top_height = point.y
				top_points = points
				top_basis = transform.basis
	if top_points.is_empty():
		return null
	# The sheet lies in the two mesh axes that are most horizontal.
	var axes: Array[Vector3] = []
	var up_index := 0
	for i in 3:
		if absf(top_basis[i].normalized().y) > absf(top_basis[up_index].normalized().y):
			up_index = i
	for i in 3:
		if i != up_index:
			axes.append(Vector3(top_basis[i].x, 0.0, top_basis[i].z).normalized())
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point in top_points:
		var projected := Vector2(point.dot(axes[0]), point.dot(axes[1]))
		low = low.min(projected)
		high = high.max(projected)
	var extent := high - low
	var middle := (low + high) * 0.5
	var center := axes[0] * middle.x + axes[1] * middle.y
	var long_index := 0 if extent.x >= extent.y else 1
	var forward := axes[long_index]
	var right := axes[1 - long_index]
	var rectangle := DOCUMENT_RECTS[posmod(seed_value, DOCUMENT_RECTS.size())]
	if posmod(seed_value, DOCUMENT_RECTS.size() * 2) >= DOCUMENT_RECTS.size():
		forward = -forward
		right = -right
	var fit := minf(extent[1 - long_index] * 0.86 / rectangle.size.x, extent[long_index] * 0.86 / rectangle.size.y)
	var half := rectangle.size * fit * 0.5
	if right.cross(forward).y < 0.0:
		right = -right # Keep the print readable rather than mirrored.
	var columns := 6
	var rows := 8
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var atlas := Vector2(DOCUMENT_ATLAS.get_width(), DOCUMENT_ATLAS.get_height())
	for row in rows + 1:
		for column in columns + 1:
			var u := float(column) / columns
			var v := float(row) / rows
			var point := center + right * (u - 0.5) * 2.0 * half.x + forward * (0.5 - v) * 2.0 * half.y
			point.y = _surface_height(faces, point, top_height) + PAPER_LIFT
			vertices.append(point)
			uvs.append((rectangle.position + rectangle.size * Vector2(u, v)) / atlas)
	var overlay := _grid_mesh(vertices, uvs, columns, rows, Vector3.UP)
	overlay.name = "DocumentPrint"
	overlay.material_override = material("document")
	visual.add_child(overlay)
	return overlay


## 0-3 sticky notes at distinct slots along the screen edges, stable per display seed.
static func add_stickers(visual: Node3D, profiles: Array, display_seed: int) -> Array[MeshInstance3D]:
	var created: Array[MeshInstance3D] = []
	if profiles.is_empty():
		return created
	var random := RandomNumberGenerator.new()
	random.seed = hash("stickers:%d" % display_seed)
	var count := random.randi_range(0, MAX_STICKERS)
	var slots := _shuffled(range(STICKER_SLOTS.size()), random)
	var frames := _shuffled(range(STICKER_FRAMES.x * STICKER_FRAMES.y), random)
	for i in count:
		var profile: Dictionary = profiles[random.randi_range(0, profiles.size() - 1)]
		var right := _vector(profile["right"])
		var up := _vector(profile["up"])
		var normal := _vector(profile["normal"])
		var screen := Vector2(float(profile["size"][0]), float(profile["size"][1]))
		var size := minf(screen.x * 0.13, screen.y * 0.35)
		var slot := STICKER_SLOTS[int(slots[i])]
		var outward := Vector2(slot.z, slot.w) * size * random.randf_range(-0.3, 0.2)
		var offset := Vector2(slot.x * screen.x * 0.5, slot.y * screen.y * 0.5) + outward
		var lift := maxf(screen.x, screen.y) * 0.012 + i * 0.0006
		var angle := random.randf_range(-0.18, 0.18)
		var sticker_right := right.rotated(normal, angle)
		var sticker_up := up.rotated(normal, angle)
		var center := _vector(profile["center"]) + right * offset.x + up * offset.y + normal * lift
		var frame := int(frames[i])
		var cell := Vector2(1.0 / STICKER_FRAMES.x, 1.0 / STICKER_FRAMES.y)
		var origin := Vector2(frame % STICKER_FRAMES.x, floori(float(frame) / STICKER_FRAMES.x)) * cell
		var vertices := PackedVector3Array()
		var uvs := PackedVector2Array()
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
			vertices.append(center + sticker_right * (corner.x - 0.5) * size + sticker_up * (0.5 - corner.y) * size)
			uvs.append(origin + cell * corner)
		var sticker := _grid_mesh(vertices, uvs, 1, 1, normal)
		sticker.name = "Sticker%d" % i
		sticker.material_override = material("sticker")
		visual.add_child(sticker)
		created.append(sticker)
	return created


static func material(kind: String) -> StandardMaterial3D:
	if _materials.has(kind):
		return _materials[kind]
	var result := StandardMaterial3D.new()
	result.resource_name = "surface_decor_" + kind
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	match kind:
		"wood", "graphite":
			result.albedo_texture = TABLE_WOOD if kind == "wood" else TABLE_GRAPHITE
			# Object-space triplanar keeps the grain on the table and on its fragments.
			result.uv1_triplanar = true
			result.uv1_scale = Vector3(0.6, 1.2, 1.2) if kind == "wood" else Vector3(1.5, 1.5, 1.5)
			result.roughness = 0.5 if kind == "wood" else 0.42
			result.metallic = 0.0 if kind == "wood" else 0.35
		"document":
			result.albedo_texture = DOCUMENT_ATLAS
			result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			result.cull_mode = BaseMaterial3D.CULL_DISABLED
			result.roughness = 1.0
		"sticker":
			result.albedo_texture = STICKER_ATLAS
			result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			result.alpha_scissor_threshold = 0.5
			result.cull_mode = BaseMaterial3D.CULL_DISABLED
			result.roughness = 0.9
	_materials[kind] = result
	return result


static func _surface_height(faces: PackedVector3Array, point: Vector3, fallback: float) -> float:
	var best := -INF
	var origin := Vector3(point.x, fallback + 1.0, point.z)
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		if point.x < minf(a.x, minf(b.x, c.x)) or point.x > maxf(a.x, maxf(b.x, c.x)):
			continue
		if point.z < minf(a.z, minf(b.z, c.z)) or point.z > maxf(a.z, maxf(b.z, c.z)):
			continue
		var hit: Variant = Geometry3D.ray_intersects_triangle(origin, Vector3.DOWN, a, b, c)
		if hit != null:
			best = maxf(best, (hit as Vector3).y)
	return best if best > -INF else fallback


static func _grid_mesh(vertices: PackedVector3Array, uvs: PackedVector2Array, columns: int, rows: int, normal: Vector3) -> MeshInstance3D:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(normal)
	var indices := PackedInt32Array()
	for row in rows:
		for column in columns:
			var a := row * (columns + 1) + column
			var b := a + 1
			var c := a + columns + 1
			var d := c + 1
			indices.append_array([a, b, c, b, d, c])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var surface := ArrayMesh.new()
	surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = surface
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func _shuffled(values: Array, random: RandomNumberGenerator) -> Array:
	var result := values.duplicate()
	for i in range(result.size() - 1, 0, -1):
		var j := random.randi_range(0, i)
		var swap: Variant = result[i]
		result[i] = result[j]
		result[j] = swap
	return result


static func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
