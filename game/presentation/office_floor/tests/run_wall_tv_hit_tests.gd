extends SceneTree
## Every authored wall TV must be reachable by a bullet from its front, not buried in a wall or column.
const LAYOUT := "res://game/presentation/office_floor/public/base_office_layout.tscn"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := (load(LAYOUT) as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	for i in 10:
		await physics_frame
	var space := scene.get_world_3d().direct_space_state
	var tvs: Array[Node] = []
	_find(scene, tvs)
	if tvs.size() < 60:
		failures += 1
		push_error("Expected the authored wall TVs, found %d" % tvs.size())
	for tv: Node3D in tvs:
		var front := tv.global_basis.z.normalized()
		var query := PhysicsRayQueryParameters3D.create(tv.global_position + front * 1.0, tv.global_position, 7)
		var hit := space.intersect_ray(query)
		if hit.is_empty() or hit.collider != tv:
			failures += 1
			push_error("Bullet does not reach the wall TV at %s" % tv.global_position)
	if not tvs.is_empty():
		var tv := tvs[0] as Node3D
		tv.call("take_projectile_hit", 80.0, tv.global_position, tv.global_basis.z, -tv.global_basis.z, "UZI")
		if tv.get("_damage").health >= 65.0:
			failures += 1
			push_error("A shot wall TV takes no damage")
	print("Wall TV hit tests: %d TVs, %d failures" % [tvs.size(), failures])
	quit(1 if failures else 0)


func _find(node: Node, out: Array[Node]) -> void:
	if "wall_TV" in str(node.get("model_path")):
		out.append(node)
	for child in node.get_children():
		_find(child, out)
