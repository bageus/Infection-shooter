extends SkeletonModifier3D
## Additive upper-body hit reaction layered over the playing clip (ADR-0040).
##
## A shot is an angular impulse on the torso: the lever from the spine to the
## hit point crossed with the shot direction. A shot to the right of the chest
## swings the right shoulder back, a high shot rocks the torso back, a shot
## from the side bends it sideways. A damped spring brings the torso back with
## a small overshoot and the head lags behind it. Hips and legs keep the clip,
## so the body does not slide as a whole. Presentation only.

const SPINE_NAMES := ["Spine", "Body", "mixamorig:Spine"]
const CHEST_NAMES := ["Chest", "Spine2", "Spine1", "mixamorig:Spine2", "mixamorig:Spine1"]
const HEAD_NAMES := ["Head", "Crown", "mixamorig:Head"]
# Share of the torso rotation carried by the lower and upper spine.
const SPINE_SHARE := 0.4
const SETTLED := 0.0005

## Spring of the torso: stiffness (1/s^2) and damping (1/s); about 2 Hz with a
## small overshoot.
var stiffness := 150.0
var damping := 13.0
## Angular speed (rad/s) given by a full-strength shot at the torso's edge.
var kick := 24.0
var max_angle := deg_to_rad(30.0)
## How fast the head catches up with the torso (1/s).
var head_follow := 9.0

var _spine := -1
var _chest := -1
var _head := -1
var _pivot := Vector3.ZERO
var _torso_length := 0.5
var _angle := Vector3.ZERO # skeleton-space rotation vector
var _velocity := Vector3.ZERO
var _head_angle := Vector3.ZERO


## Resolves the torso bones; false when the skeleton has no usable spine.
func setup(skeleton: Skeleton3D) -> bool:
	_spine = _find(skeleton, SPINE_NAMES)
	_chest = _find(skeleton, CHEST_NAMES)
	_head = _find(skeleton, HEAD_NAMES)
	if _spine < 0:
		return false
	_pivot = skeleton.get_bone_global_rest(_spine).origin
	var top := _head if _head >= 0 else _chest
	if top >= 0:
		_torso_length = maxf(0.2, _pivot.distance_to(skeleton.get_bone_global_rest(top).origin))
	return true


## Adds the impulse of a shot. world_direction is the shot's travel; with no
## direction (damage without a source) the torso just rocks back.
func push(world_point: Vector3, world_direction: Vector3, strength: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or _spine < 0:
		return
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var direction := Vector3.FORWARD
	var lever := Vector3(0.0, _torso_length * 0.6, 0.0)
	if world_direction.length_squared() > 0.0001:
		direction = (to_skeleton.basis * world_direction).normalized()
		lever = to_skeleton * world_point - _pivot
	# Hits below the spine still rock the torso a little, never pitch it forward.
	lever.y = maxf(lever.y, _torso_length * 0.25)
	var torque := (lever / _torso_length).limit_length(1.2).cross(direction)
	_velocity += torque * kick * clampf(strength, 0.0, 1.5)


func is_settled() -> bool:
	return _angle.length_squared() < SETTLED * SETTLED and _velocity.length_squared() < SETTLED


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or _spine < 0:
		return
	_step(minf(delta, 0.05))
	if is_settled() and _head_angle.length_squared() < SETTLED * SETTLED:
		_angle = Vector3.ZERO
		_velocity = Vector3.ZERO
		_head_angle = Vector3.ZERO
		return
	if _chest >= 0:
		_rotate_bone(skeleton, _spine, _angle * SPINE_SHARE)
		_rotate_bone(skeleton, _chest, _angle * (1.0 - SPINE_SHARE))
	else:
		_rotate_bone(skeleton, _spine, _angle)
	if _head >= 0:
		# The head keeps its gaze for a moment, then whips after the torso.
		_rotate_bone(skeleton, _head, (_head_angle - _angle) * 0.8)


func _step(delta: float) -> void:
	_velocity += (-stiffness * _angle - damping * _velocity) * delta
	_angle += _velocity * delta
	if _angle.length() > max_angle:
		_angle = _angle.normalized() * max_angle
		_velocity *= 0.5
	_head_angle = _head_angle.lerp(_angle, 1.0 - exp(-head_follow * delta))


# Turns a bone about its joint by a skeleton-space rotation vector.
func _rotate_bone(skeleton: Skeleton3D, bone: int, rotation_vector: Vector3) -> void:
	var angle := rotation_vector.length()
	if angle < 0.00001:
		return
	var parent := skeleton.get_bone_parent(bone)
	var parent_rotation := Quaternion.IDENTITY
	if parent >= 0:
		parent_rotation = skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion()
	var turn := Quaternion(rotation_vector / angle, angle)
	var local := skeleton.get_bone_pose_rotation(bone)
	skeleton.set_bone_pose_rotation(bone, (parent_rotation.inverse() * turn * parent_rotation * local).normalized())


static func _find(skeleton: Skeleton3D, names: Array) -> int:
	for bone_name: String in names:
		var index := skeleton.find_bone(bone_name)
		if index >= 0:
			return index
	return -1
