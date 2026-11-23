extends RefCounted
## A dead body's raised legs come down onto the floor (or whatever solid thing is under the foot).
## Used where a corpse is left in a pose: a death clip frozen on a ledge and a ragdoll that stops.

const WORLD_MASK := 1
const SWING_RATE := 2.6 # rad/s when played over time
## The foot counts as resting when solid ground is this close below the ankle.
const REST_DISTANCE := 0.1
const MAX_STEPS := 40
const STEP_ANGLE := 0.04


## Swings both thighs by up to `angle` radians about the horizontal `axis` (perpendicular to the body's
## length) in the direction that lowers the foot. Returns true while some leg still moved.
static func lower(skeleton: Skeleton3D, world: World3D, axis: Vector3, exclude: Array[RID], angle: float) -> bool:
	var moved := false
	for side in ["L", "R"]:
		var thigh := skeleton.find_bone(side + "_Thigh")
		var foot := skeleton.find_bone(side + "_Foot")
		if thigh < 0 or foot < 0:
			continue
		var at := _point(skeleton, foot)
		moved = _straighten(skeleton, skeleton.find_bone(side + "_Shin"), angle) or moved
		if _rests(world, at, exclude):
			continue
		var best := 0.0
		var best_y := at.y
		for direction: float in [1.0, -1.0]:
			var before := skeleton.get_bone_pose_rotation(thigh)
			_swing(skeleton, thigh, axis, direction * angle)
			var y := _point(skeleton, foot).y
			skeleton.set_bone_pose_rotation(thigh, before)
			if y < best_y - 0.0001:
				best = direction
				best_y = y
		if best != 0.0:
			_swing(skeleton, thigh, axis, best * angle)
			moved = true
	return moved


## Settles at once: the legs come all the way down.
static func drop(skeleton: Skeleton3D, world: World3D, body_axis: Vector3, exclude: Array[RID]) -> void:
	var length := Vector3(body_axis.x, 0.0, body_axis.z)
	if length.is_zero_approx():
		return
	var axis := Vector3.UP.cross(length).normalized()
	for step in MAX_STEPS:
		if not lower(skeleton, world, axis, exclude, STEP_ANGLE):
			return


## Brings the legs down over `seconds`, a moment after a clip has ended on a pose with raised legs.
static func settle_over(owner: Node3D, skeleton: Skeleton3D, delay: float, seconds: float) -> void:
	await owner.get_tree().create_timer(delay).timeout
	var left := seconds
	while left > 0.0 and is_instance_valid(owner) and is_instance_valid(skeleton) and skeleton.is_inside_tree():
		var delta := owner.get_process_delta_time()
		left -= delta
		var hips := skeleton.find_bone("Hips")
		var head := skeleton.find_bone("Head")
		if hips < 0 or head < 0:
			return
		var along: Vector3 = skeleton.global_basis * (skeleton.get_bone_global_pose(head).origin - skeleton.get_bone_global_pose(hips).origin)
		var flat := Vector3(along.x, 0.0, along.z)
		var exclude: Array[RID] = []
		if owner is CollisionObject3D:
			exclude.append(owner.get_rid())
		if flat.is_zero_approx() or not lower(skeleton, owner.get_world_3d(), Vector3.UP.cross(flat).normalized(), exclude, SWING_RATE * delta):
			return
		await owner.get_tree().process_frame


# The knee unbends toward the rest pose (a straight leg); true while it still turns.
static func _straighten(skeleton: Skeleton3D, shin: int, angle: float) -> bool:
	if shin < 0:
		return false
	var now := skeleton.get_bone_pose_rotation(shin)
	var rest := skeleton.get_bone_rest(shin).basis.get_rotation_quaternion()
	var left := now.angle_to(rest)
	if left < 0.03:
		return false
	skeleton.set_bone_pose_rotation(shin, now.slerp(rest, minf(1.0, angle * 1.5 / left)))
	return true


static func _rests(world: World3D, foot_at: Vector3, exclude: Array[RID]) -> bool:
	var query := PhysicsRayQueryParameters3D.create(foot_at + Vector3.UP * 0.05, foot_at - Vector3.UP * REST_DISTANCE, WORLD_MASK, exclude)
	return not world.direct_space_state.intersect_ray(query).is_empty()


static func _swing(skeleton: Skeleton3D, thigh: int, axis: Vector3, angle: float) -> void:
	var parent := skeleton.get_bone_parent(thigh)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var local_axis := (parent_basis.inverse() * (skeleton.global_basis.inverse() * axis)).normalized()
	skeleton.set_bone_pose_rotation(thigh, Quaternion(local_axis, angle) * skeleton.get_bone_pose_rotation(thigh))


static func _point(skeleton: Skeleton3D, bone: int) -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
