extends RefCounted
const FLOOR_POSES := ["back", "stomach", "left_side", "right_side"]

static func configure_new(node: Node3D, preview: Node3D) -> void:
	if not node.has_method("configure_decor_pose"):
		return
	var config: Dictionary = preview.call("get_decor_pose") if preview != null and preview != node and preview.has_method("get_decor_pose") else {"seed": randi_range(1, 2147483646), "pose": "auto"}
	node.call("configure_decor_pose", config)


static func place(node: Node3D) -> void:
	if not node.has_method("get_decor_pose") or not node.has_method("get_planner_bounds"):
		return
	var config: Dictionary = node.call("get_decor_pose")
	var origin := node.global_position
	var wall: Dictionary = node.get_meta("decor_probe_wall", {})
	var old: Vector3 = node.get_meta("decor_probe_position", Vector3.INF)
	if old.distance_to(origin) > .2:
		wall = _wall(node, origin)
		node.set_meta("decor_probe_wall", wall)
		node.set_meta("decor_probe_position", origin)
	var seed_value := int(config["seed"])
	var pose: String = FLOOR_POSES[posmod(seed_value, 4)]
	if not wall.is_empty() and posmod(seed_value, 3) != 0:
		pose = "seated" if posmod(seed_value, 2) == 0 else "seated_side"
	var facing := atan2((wall["normal"] as Vector3).x, (wall["normal"] as Vector3).z) if pose.begins_with("seated") else float(posmod(seed_value, 6283)) / 1000.0 - PI
	if config.get("pose") != pose or not is_equal_approx(float(config.get("facing", 0.0)), facing):
		config["pose"] = pose
		config["facing"] = facing
		node.call("configure_decor_pose", config)
	if pose.begins_with("seated"):
		var normal: Vector3 = wall["normal"]
		var bounds: AABB = node.call("get_planner_bounds")
		var back := INF
		for corner in 8:
			back = minf(back, (node.global_transform * bounds.get_endpoint(corner)).dot(normal))
		node.global_position += normal * ((wall["position"] as Vector3).dot(normal) + .025 - back)


static func _wall(node: Node3D, position: Vector3) -> Dictionary:
	var nearest := .85
	var result: Dictionary = {}
	for index in 12:
		var direction := Vector3.FORWARD.rotated(Vector3.UP, TAU * float(index) / 12.0)
		var origin := position + Vector3.UP * .65
		var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * .85, 1)
		var hit := node.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and absf((hit["normal"] as Vector3).y) < .1:
			var distance := origin.distance_to(hit["position"])
			if distance < nearest:
				nearest = distance
				result = hit
	return result
