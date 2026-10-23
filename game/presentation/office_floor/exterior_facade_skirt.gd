extends MeshInstance3D
## One mesh for the building under all exterior windows. Neighbouring windows merge into a run,
## and the window grid is drawn by exterior_facade.gdshader, so there is no node per window.
## Visual only: no collision and no shadow.

const CITY_GROUND_Y := -65.4 # FogGround in public/city_backdrop.gd
const SHADER := preload("res://game/presentation/office_floor/exterior_facade.gdshader")
const JOIN_GAP := 0.05

var _windows: Array[Node3D] = []


func _init() -> void:
	name = "ExteriorFacadeSkirt"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material_override = material
	set_process(false)


func add_window(window: Node3D) -> void:
	if not _windows.has(window):
		_windows.append(window)
		set_process(true)


func remove_window(window: Node3D) -> void:
	if _windows.has(window):
		_windows.erase(window)
		set_process(true)


func _process(_delta: float) -> void:
	set_process(false)
	_rebuild()


func _rebuild() -> void:
	var runs := {}
	for window in _windows:
		var frame := window.find_child("frame", true, false) as MeshInstance3D
		if frame == null or frame.mesh == null:
			continue
		var bounds := frame.global_transform * frame.get_aabb()
		if bounds.position.y <= CITY_GROUND_Y:
			continue
		var along_x := bounds.size.x >= bounds.size.z
		var along := Vector2(bounds.position.x, bounds.end.x) if along_x else Vector2(bounds.position.z, bounds.end.z)
		var depth := bounds.get_center().z if along_x else bounds.get_center().x
		var thickness := bounds.size.z if along_x else bounds.size.x
		var key := Vector3i(int(along_x), roundi(depth * 20.0), roundi(bounds.position.y * 20.0))
		if not runs.has(key):
			runs[key] = []
		runs[key].append({"along": along, "depth": depth, "thickness": thickness, "top": bounds.position.y, "x": along_x})
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for key in runs:
		var list: Array = runs[key]
		list.sort_custom(func(a, b): return a.along.x < b.along.x)
		var start: Dictionary = list[0]
		var end_along: float = start.along.y
		for i in range(1, list.size() + 1):
			if i < list.size() and list[i].along.x <= end_along + JOIN_GAP:
				end_along = maxf(end_along, list[i].along.y)
				continue
			_add_run(start, end_along, vertices, normals, uvs, colors, indices)
			if i < list.size():
				start = list[i]
				end_along = start.along.y
	if vertices.is_empty():
		mesh = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var skirt := ArrayMesh.new()
	skirt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	skirt.custom_aabb = AABB(Vector3(-200, CITY_GROUND_Y, -200), Vector3(400, 70, 400))
	mesh = skirt


## Adds an open-top, open-bottom box for one run, in this node's local space.
func _add_run(first: Dictionary, end_along: float, vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array) -> void:
	var a0: float = first.along.x
	var half: float = first.thickness * 0.5
	var top: float = first.top
	var height := top - CITY_GROUND_Y
	# Corners as (along, depth) pairs walked around the footprint; each edge is one wall.
	var corners := [Vector2(a0, first.depth - half), Vector2(end_along, first.depth - half), Vector2(end_along, first.depth + half), Vector2(a0, first.depth + half)]
	var inverse := global_transform.affine_inverse()
	for edge in 4:
		var p := corners[edge] as Vector2
		var q := corners[(edge + 1) % 4] as Vector2
		var is_face := edge % 2 == 0
		var base := vertices.size()
		for corner in [[p, 0.0], [q, 0.0], [q, 1.0], [p, 1.0]]:
			var xz := corner[0] as Vector2
			var world := Vector3(xz.x, top - corner[1] * height, xz.y) if first.x else Vector3(xz.y, top - corner[1] * height, xz.x)
			vertices.append(inverse * world)
			uvs.append(Vector2((xz.x - a0) if is_face else 0.0, corner[1] * height))
			colors.append(Color(1, 1, 1, 1.0 if is_face else 0.0))
		var edge_dir := (q - p).normalized()
		var normal2 := Vector2(edge_dir.y, -edge_dir.x)
		var normal := Vector3(normal2.x, 0.0, normal2.y) if first.x else Vector3(normal2.y, 0.0, normal2.x)
		normal = (inverse.basis * normal).normalized()
		for i in 4:
			normals.append(normal)
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
