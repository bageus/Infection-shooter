extends SceneTree
## Placed spent casings draw as one cylinder of the original size instead of a 3-4 surface model.
const SIMPLE := preload("res://game/bootstrap/app/planning_simple_casing.gd")
const RIFLE := "res://models/objects/enviroments/12/12_rifle_casing.glb"
const SHOTGUN := "res://models/objects/enviroments/12/12_shotgun_casing.glb"
const MOUSE := "res://models/objects/enviroments/05/05_computer_mouse.glb"
var failures := 0


func _initialize() -> void:
	await process_frame
	for path in [RIFLE, SHOTGUN]:
		var node := (load(path) as PackedScene).instantiate() as Node3D
		root.add_child(node)
		var before := _box(node)
		var surfaces_before := _surfaces(node)
		SIMPLE.apply(node, path)
		_check(_surfaces(node) == 1, "%s draws one surface (model has %d)" % [path.get_file(), surfaces_before])
		_check(_box(node).size.distance_to(before.size) < before.size.length() * 0.15, "%s keeps its size: %s vs %s" % [path.get_file(), _box(node).size, before.size])
		_check(_box(node).get_center().distance_to(before.get_center()) < 0.01, "%s keeps its place" % path.get_file())
	var other := (load(MOUSE) as PackedScene).instantiate() as Node3D
	root.add_child(other)
	var count := _surfaces(other)
	SIMPLE.apply(other, MOUSE)
	_check(_surfaces(other) == count, "other models are untouched")
	print("Simple casing tests: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _surfaces(node: Node) -> int:
	var total := 0
	for mesh_node in node.find_children("*", "MeshInstance3D", true, false):
		total += (mesh_node as MeshInstance3D).mesh.get_surface_count()
	return total


func _box(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh_node: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var part := mesh_node.global_transform * mesh_node.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)
