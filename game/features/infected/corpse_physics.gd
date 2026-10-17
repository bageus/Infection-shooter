extends RefCounted
## Build bounded articulated collision volumes from the existing body-part rig.
var simulator: PhysicalBoneSimulator3D
var skeleton: Skeleton3D
var _bones: Dictionary = {}
var _parts: Node
var _guard: Node
const GUARD := preload("res://game/features/infected/corpse_guard.gd")


func setup(parts: Node) -> void:
	_parts = parts
	skeleton = parts.get("skeleton") as Skeleton3D
	if skeleton == null:
		return
	simulator = PhysicalBoneSimulator3D.new()
	simulator.name = "CorpsePhysics"
	simulator.active = false
	skeleton.add_child(simulator)
	var definitions: Dictionary = parts.get("parts")
	var segments: Array[Dictionary] = []
	for label: StringName in definitions:
		var definition: Dictionary = definitions[label]
		if definition["severed"]:
			continue
		_bones[label] = []
		for segment: Dictionary in definition["segments"]:
			var entry := segment.duplicate()
			entry["part"] = label
			segments.append(entry)
	# Parents must exist and have their posed transform before child joints bind.
	segments.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["bone"]) < int(b["bone"]))
	for segment in segments:
		var bone := _build(segment)
		_bones[segment["part"]].append(bone)
	for bone: PhysicalBone3D in simulator.get_children():
		bone.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(bone.get_bone_id()) * bone.body_offset
	for bone: PhysicalBone3D in simulator.get_children():
		bone.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
		bone.set("joint_constraints/swing_span", 45.0)
		bone.set("joint_constraints/twist_span", 25.0)
	# All volumes are linked at skeleton joints; own limbs never collide.
	var volumes := simulator.get_children()
	for i in volumes.size():
		for j in range(i + 1, volumes.size()):
			(volumes[i] as PhysicalBone3D).add_collision_exception_with(volumes[j])
	_guard = GUARD.new()
	_guard.name = "CorpseGuard"
	skeleton.add_child(_guard)
	_guard.set_physics_process(false)
	_refresh_guard()
	parts.connect("part_severed", _severed)


func _build(segment: Dictionary) -> PhysicalBone3D:
	var index := int(segment["bone"])
	var bone := PhysicalBone3D.new()
	bone.name = "Physics_" + skeleton.get_bone_name(index)
	bone.set("bone_name", skeleton.get_bone_name(index))
	bone.collision_layer = 0 # Bullet hits keep using damage-aware bone hitboxes.
	bone.collision_mask = 1
	bone.mass = 3.0
	bone.linear_damp = .7
	bone.angular_damp = 2.5
	bone.friction = .9
	bone.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
	var rest := skeleton.get_bone_global_rest(index)
	var start: Vector3 = rest.affine_inverse() * Vector3(segment["start"])
	var end: Vector3 = rest.affine_inverse() * Vector3(segment["end"])
	var axis := end - start
	var radius := clampf(float(segment["radius"]) * 1.5, .03, 1.0)
	var capsule := CapsuleShape3D.new()
	var world_bone := skeleton.global_transform * skeleton.get_bone_global_pose(index)
	var world_radius := radius * world_bone.basis.get_scale().abs()[world_bone.basis.get_scale().abs().max_axis_index()]
	capsule.radius = world_radius
	capsule.height = (world_bone.basis * axis).length() + world_radius * 2.0
	var alignment := Basis(Quaternion(Vector3.UP, axis.normalized())) if axis.length_squared() > .00001 else Basis.IDENTITY
	# Physics bodies have unit scale. Offset inverse restores the authored skin scale.
	var physical_basis := (world_bone.basis * alignment).orthonormalized()
	var offset_basis := world_bone.basis.inverse() * physical_basis
	bone.body_offset = Transform3D(offset_basis, (start + end) * .5)
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	bone.add_child(shape)
	simulator.add_child(bone)
	return bone


func set_enabled(enabled: bool) -> void:
	if not is_instance_valid(simulator):
		return
	if enabled:
		simulator.active = true
		simulator.physical_bones_start_simulation()
		_guard.set_physics_process(not _guard.frozen)
	else:
		_guard.set_physics_process(false)
		simulator.physical_bones_stop_simulation()
		simulator.active = false


## Transfer the simulated pose into the skeleton before releasing its slot.
## Stopping alone restores the pre-death animation pose. Body offsets include
## the authored skin scale, so preserve the full transform rather than rotation.
func freeze_pose() -> void:
	if not is_instance_valid(simulator) or not is_instance_valid(skeleton):
		return
	var poses: Dictionary = {}
	var to_skeleton := skeleton.global_transform.affine_inverse()
	for bone: PhysicalBone3D in simulator.get_children():
		if not bone.is_queued_for_deletion():
			poses[bone.get_bone_id()] = to_skeleton * bone.global_transform * bone.body_offset.affine_inverse()
	set_enabled(false)
	# Skeleton parents precede their children; global -> local conversion must
	# use the retained parent pose, not the old animation pose.
	for index in skeleton.get_bone_count():
		if poses.has(index):
			skeleton.set_bone_global_pose(index, poses[index])


## Gives every bone the same start velocity; the upper body leads a little so a
## standing body topples instead of sliding on its feet. Call after set_enabled.
func launch(velocity: Vector3) -> void:
	if not is_instance_valid(simulator):
		return
	var bones := simulator.get_children()
	var middle := 0.0
	var lift := _floor_lift()
	for bone: PhysicalBone3D in bones:
		bone.global_position.y += lift
		middle += bone.global_position.y / bones.size()
	for bone: PhysicalBone3D in bones:
		bone.linear_velocity = velocity * (1.0 if bone.global_position.y >= middle else 0.5)


# Feet of a standing body sink a little into the floor; the solver would shove
# them out violently, so the whole body starts just above the surface.
func _floor_lift() -> float:
	var space := simulator.get_world_3d().direct_space_state
	var lift := 0.0
	for bone: PhysicalBone3D in simulator.get_children():
		var capsule := (bone.get_child(0) as CollisionShape3D).shape as CapsuleShape3D
		var axis_y := absf((bone.global_basis * Vector3.UP).normalized().y)
		var lowest := bone.global_position.y - (axis_y * (capsule.height * 0.5 - capsule.radius) + capsule.radius)
		var top := bone.global_position + Vector3.UP * 0.5
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(top, Vector3(top.x, lowest - 0.5, top.z), 1))
		if not hit.is_empty():
			lift = maxf(lift, float(hit["position"].y) - lowest + 0.01)
	return minf(lift, 0.3)


## Lets the body fall through the floor, then the owner hides it.
func sink() -> void:
	if not is_instance_valid(simulator):
		return
	_guard.set_physics_process(false)
	for bone: PhysicalBone3D in simulator.get_children():
		bone.collision_mask = 0
		bone.gravity_scale = 1.0
		bone.linear_damp = 0.0
		bone.linear_velocity = Vector3.DOWN * 1.5


func _severed(part: StringName, _piece: RigidBody3D) -> void:
	for bone: PhysicalBone3D in _bones.get(part, []):
		if is_instance_valid(bone):
			bone.queue_free()
	_bones.erase(part)
	_refresh_guard.call_deferred()


func _refresh_guard() -> void:
	if not is_instance_valid(_guard):
		return
	var alive: Array[PhysicalBone3D] = []
	for bone: PhysicalBone3D in simulator.get_children():
		if not bone.is_queued_for_deletion():
			alive.append(bone)
	_guard.setup(alive, skeleton)


func dispose() -> void:
	set_enabled(false)
	if is_instance_valid(_parts) and _parts.is_connected("part_severed", _severed):
		_parts.disconnect("part_severed", _severed)
	if is_instance_valid(_guard):
		_guard.free()
	if is_instance_valid(simulator):
		simulator.free()
	_bones.clear()
	_parts = null
	simulator = null
	skeleton = null
