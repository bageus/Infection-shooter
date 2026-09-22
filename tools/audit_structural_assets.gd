extends SceneTree

const GRID_STEP := 0.25
const STRUCTURAL_DIR := "res://game/presentation/office_floor/public/structural"
const TARGET_SPANS := {
	"GlassWallFull": 4.0,
	"GlassPartitionHalf": 4.0,
	"GlassPartitionBlinds": 4.0,
	"SlidingGlassDoor": 4.0,
}

func _initialize() -> void:
	var scenes := _find_structural_scenes()
	if scenes.is_empty():
		push_error("No structural scenes found in %s" % STRUCTURAL_DIR)
		quit(1)
		return
	print("asset,path,size_x,size_y,size_z,min_x,min_y,min_z,max_x,max_y,max_z,origin_to_floor,grid_x,grid_z,target_span,span_error,status")
	var failed := false
	for path in scenes:
		var result := _audit_scene(path)
		if result.is_empty():
			failed = true
			continue
		print(result["csv"])
		if result["status"] == "ERROR":
			failed = true
	quit(1 if failed else 0)

func _find_structural_scenes() -> PackedStringArray:
	var paths := PackedStringArray()
	var dir := DirAccess.open(STRUCTURAL_DIR)
	if dir == null:
		push_error("Cannot open %s" % STRUCTURAL_DIR)
		return paths
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".tscn"):
			paths.append("%s/%s" % [STRUCTURAL_DIR, name])
		name = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths

func _audit_scene(path: String) -> Dictionary:
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Cannot load %s" % path)
		return {}
	var root := packed.instantiate()
	get_root().add_child(root)
	var visual := root.get_node_or_null("Visual") as Node3D
	if visual == null:
		push_error("%s has no Visual Node3D" % path)
		root.queue_free()
		return {}
	var bounds := _combined_bounds(visual, root)
	if bounds.is_empty():
		push_error("%s has no MeshInstance3D bounds" % path)
		root.queue_free()
		return {}
	var min_v: Vector3 = bounds["min"]
	var max_v: Vector3 = bounds["max"]
	var size := max_v - min_v
	var target_span := float(TARGET_SPANS.get(root.name, 0.0))
	var span_error := 0.0 if target_span <= 0.0 else min(abs(size.x - target_span), abs(size.z - target_span))
	var grid_x := _grid_error(size.x)
	var grid_z := _grid_error(size.z)
	var status := "OK"
	if target_span > 0.0 and span_error > 0.01:
		status = "CHECK"
	var values := [
		root.name, path, size.x, size.y, size.z,
		min_v.x, min_v.y, min_v.z, max_v.x, max_v.y, max_v.z,
		min_v.y, grid_x, grid_z, target_span, span_error, status
	]
	root.queue_free()
	return {"csv": ",".join(values.map(func(v): return str(v))), "status": status}

func _combined_bounds(node: Node, root: Node3D) -> Dictionary:
	var has_bounds := false
	var min_v := Vector3.ZERO
	var max_v := Vector3.ZERO
	for child in _all_nodes(node):
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			if mesh_instance.mesh == null:
				continue
			var aabb := mesh_instance.get_aabb()
			var to_root := root.global_transform.affine_inverse() * mesh_instance.global_transform
			for corner in _aabb_corners(aabb):
				var p := to_root * corner
				if not has_bounds:
					min_v = p
					max_v = p
					has_bounds = true
				else:
					min_v = min_v.min(p)
					max_v = max_v.max(p)
	if not has_bounds:
		return {}
	return {"min": min_v, "max": max_v}

func _all_nodes(root: Node) -> Array[Node]:
	var result: Array[Node] = [root]
	var index := 0
	while index < result.size():
		var current := result[index]
		for child in current.get_children():
			result.append(child)
		index += 1
	return result

func _aabb_corners(aabb: AABB) -> Array[Vector3]:
	var p := aabb.position
	var e := aabb.end
	return [
		Vector3(p.x, p.y, p.z), Vector3(e.x, p.y, p.z),
		Vector3(p.x, e.y, p.z), Vector3(e.x, e.y, p.z),
		Vector3(p.x, p.y, e.z), Vector3(e.x, p.y, e.z),
		Vector3(p.x, e.y, e.z), Vector3(e.x, e.y, e.z),
	]

func _grid_error(value: float) -> float:
	return abs(value - round(value / GRID_STEP) * GRID_STEP)
