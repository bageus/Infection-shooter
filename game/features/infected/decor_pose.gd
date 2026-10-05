extends RefCounted
const MESH := preload("res://game/features/infected/body_part_mesh.gd")
const FLOOR_POSES := ["back", "stomach", "left_side", "right_side"]

static func apply(body: Node3D, skeleton: Skeleton3D, config: Dictionary) -> void:
	var authored_scale := body.scale
	var rng := RandomNumberGenerator.new()
	rng.seed = int(config.get("seed", 1))
	var pose := str(config.get("pose", "back"))
	if pose == "auto":
		pose = FLOOR_POSES[rng.randi_range(0, 3)]
	skeleton.reset_bone_poses()
	body.position = Vector3.ZERO
	var yaw := float(config.get("facing", rng.randf_range(-PI, PI)))
	var tilt := Vector3.ZERO
	match pose:
		"back": tilt.x = -PI * .5
		"stomach": tilt.x = PI * .5
		"left_side": tilt.z = PI * .5
		"right_side": tilt.z = -PI * .5
		"seated", "seated_side":
			var hips := skeleton.find_bone("Hips")
			if hips >= 0:
				skeleton.set_bone_pose_position(hips, Vector3.DOWN * .52)
			for side in ["L", "R"]:
				_rotate(skeleton, side + "_Thigh", Vector3.RIGHT, -1.45 + rng.randf_range(-.12, .12))
				_rotate(skeleton, side + "_Shin", Vector3.RIGHT, 1.5 + rng.randf_range(-.12, .12))
			_rotate(skeleton, "Spine", Vector3.RIGHT, .12)
			if pose == "seated_side":
				tilt.z = .6 if rng.randf() > .5 else -.6
	for side in ["L", "R"]:
		_rotate(skeleton, side + "_UpperArm", Vector3.RIGHT, rng.randf_range(-.55, .15))
		_rotate(skeleton, side + "_Forearm", Vector3.RIGHT, rng.randf_range(-.8, -.15))
	_rotate(skeleton, "Neck", Vector3.FORWARD, rng.randf_range(-.2, .2))
	body.basis = Basis(Vector3.UP, yaw) * Basis.from_euler(tilt) * Basis.from_scale(authored_scale)


static func _rotate(skeleton: Skeleton3D, bone_name: String, axis: Vector3, angle: float) -> void:
	var index := skeleton.find_bone(bone_name)
	if index >= 0:
		skeleton.set_bone_pose_rotation(index, Quaternion(axis, angle))


static func bounds(parts: Node, owner_body: Node3D) -> AABB:
	var skeleton: Skeleton3D = parts.get("skeleton")
	var to_local := owner_body.global_transform.affine_inverse()
	var result := AABB()
	var found := false
	for entry: Dictionary in parts.get("_entries"):
		var data: Dictionary = entry["data"]
		var transforms: Dictionary = {}
		for bone: int in data.binds:
			transforms[bone] = skeleton.global_transform * skeleton.get_bone_global_pose(bone) * (data.binds[bone] as Transform3D)
		for surface: Dictionary in data.surfaces:
			var vertices: PackedVector3Array = surface.vertices
			for index in vertices.size():
				var transform: Transform3D = MESH._blend(transforms, surface.bones, surface.weights, int(surface.stride), index)
				var point := to_local * (transform * vertices[index])
				result = result.expand(point) if found else AABB(point, Vector3.ZERO)
				found = true
	return result
