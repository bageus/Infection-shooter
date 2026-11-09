extends SceneTree
const MERGE := preload("res://game/bootstrap/app/planning_static_merge.gd")
const WALL := "res://game/presentation/office_floor/public/structural/wall_straight.tscn"
var failures := 0


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var placed: Array = []
	for i in 3:
		var wall := (load(WALL) as PackedScene).instantiate() as Node3D
		world.add_child(wall)
		wall.position = Vector3(i * 2.0, 0, 1)
		wall.rotation_degrees.y = 90 * i
		wall.set_meta("planning_scene_path", WALL)
		placed.append(wall)
	var other := Node3D.new()
	other.set_meta("planning_scene_path", "res://x/door.tscn")
	world.add_child(other)
	placed.append(other)
	await process_frame
	var originals: Array[MeshInstance3D] = []
	var vertex_total := 0
	for wall in placed.slice(0, 3):
		for found in wall.find_children("*", "MeshInstance3D", true, false):
			if not (found as MeshInstance3D).visible or absf((found as MeshInstance3D).global_basis.determinant()) < 0.000001:
				continue
			originals.append(found)
			for surface in (found as MeshInstance3D).mesh.get_surface_count():
				vertex_total += ((found as MeshInstance3D).mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var merged := MERGE.merge(placed, world)
	_check(merged == originals.size() and merged > 0, "every wall mesh was merged (%d of %d)" % [merged, originals.size()])
	_check(originals.all(func(m: MeshInstance3D) -> bool: return not m.visible), "originals are hidden")
	var holder := world.get_node("StaticMerged")
	var merged_vertices := 0
	var box := AABB()
	for child in holder.get_children():
		merged_vertices += ((child as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		box = box.merge((child as MeshInstance3D).get_aabb()) if box.size != Vector3.ZERO else (child as MeshInstance3D).get_aabb()
	_check(merged_vertices == vertex_total, "no vertex lost (%d vs %d)" % [merged_vertices, vertex_total])
	_check(holder.get_child_count() < originals.size(), "fewer meshes than before (%d vs %d)" % [holder.get_child_count(), originals.size()])
	_check(box.position.x < 0.5 and box.end.x > 3.5, "merged meshes sit at the walls' world positions")
	MERGE.restore(self)
	await process_frame
	_check(originals.all(func(m: MeshInstance3D) -> bool: return m.visible), "restore shows the originals again")
	_check(not world.has_node("StaticMerged"), "restore removes the merged meshes")
	print("Static merge tests: %d failure(s)" % failures)
	quit(failures)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
