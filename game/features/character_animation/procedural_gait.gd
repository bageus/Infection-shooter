extends SkeletonModifier3D
## Speed-synchronised leg gait layered over authored upper-body clips
## (ADR-0016). The legs are rebuilt from the rest pose every frame: thighs
## swing along the actual movement direction, knees lift in the swing phase,
## feet stay near level and the hips bob twice per cycle. Cadence and stride
## follow the character's real speed, so feet do not slide or limp.
## Presentation only: reads the character's velocity, never changes it.

const HIPS_NAMES := ["Hips", "mixamorig:Hips", "hips", "pelvis"]
const THIGH_NAMES := ["UpLeg", "Thigh", "UpperLeg"]
const SHIN_NAMES := ["Leg", "Shin", "LowerLeg", "Calf"]
const FOOT_NAMES := ["Foot"]
const SIDE_PREFIXES := [["Left", "L_", "left_"], ["Right", "R_", "right_"]]

## Emitted when a foot lands (side 0 = left, 1 = right) while the gait owns the legs.
signal stepped(side: int, speed: float)

var character: CharacterBody3D
## Cycles per second at walking pace and the cap reached when sprinting.
var base_cadence := 0.95
var cadence_per_mps := 0.22
var max_cadence := 2.5
var max_swing_degrees := 40.0
var knee_lift_degrees := 62.0
var bob_ratio := 0.035
var max_leg_yaw := 45.0

var phase := 0.0
var weight := 0.0
var _hips := -1
var _legs: Array = [] # [[thigh, shin, foot], ...] left first
var _leg_length := 0.9
var _ready_bones := false


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or character == null:
		return
	if not _ready_bones:
		_ready_bones = _resolve_bones(skeleton)
		if not _ready_bones:
			return
	var to_skeleton := skeleton.global_basis.inverse()
	var world_scale := skeleton.global_basis.get_scale().y
	var velocity := Vector3(character.velocity.x, 0.0, character.velocity.z)
	var speed := velocity.length()
	weight = move_toward(weight, smoothstep(0.15, 0.9, speed), delta * 6.0)
	if weight <= 0.001:
		return
	var leg_world := _leg_length * world_scale
	var cadence := minf(max_cadence, base_cadence + cadence_per_mps * speed)
	var previous_phase := phase
	phase = fmod(phase + delta * cadence * TAU, TAU)
	if weight > 0.5:
		# A foot is planted when its leg reaches the front of the swing.
		for side in 2:
			var plant := PI * 0.5 + PI * float(side)
			if _crossed(previous_phase, phase, plant):
				stepped.emit(side, speed)
	var flight := 1.0 + 0.25 * smoothstep(3.5, 6.0, speed)
	var stride := speed / maxf(cadence, 0.1) / flight
	var swing := minf(deg_to_rad(max_swing_degrees), asin(clampf(stride / maxf(4.0 * leg_world, 0.01), 0.0, 0.95)))
	var run := smoothstep(3.0, 6.5, speed)
	var direction := (to_skeleton * velocity).normalized() if speed > 0.05 else Vector3.BACK
	direction.y = 0.0
	direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.BACK
	# Sideways travel turns the legs toward it (up to max_leg_yaw) and steps
	# diagonally instead of splaying the legs apart.
	var forward_sign := 1.0 if direction.z >= -0.2 else -1.0
	var yaw := clampf(atan2(direction.x, absf(direction.z)), -deg_to_rad(max_leg_yaw), deg_to_rad(max_leg_yaw)) * forward_sign
	var leg_yaw := Quaternion(Vector3.UP, yaw)
	var step_direction := leg_yaw * Vector3(0.0, 0.0, forward_sign)
	var swing_axis := Vector3.DOWN.cross(step_direction).normalized()
	var lateral := leg_yaw * Vector3.RIGHT
	# Hips: vertical bob, lowest when the legs are spread.
	var hips_pose := skeleton.get_bone_pose_position(_hips)
	var bob := bob_ratio * (1.0 + 0.8 * run) * _leg_length * 0.5 * (1.0 - cos(2.0 * phase)) * weight
	skeleton.set_bone_pose_position(_hips, hips_pose + _parent_basis_inverse(skeleton, _hips) * Vector3(0.0, -bob, 0.0))
	var hips_global := skeleton.get_bone_global_pose(_hips)
	for side in 2:
		var bones: Array = _legs[side]
		var local_phase := phase + (0.0 if side == 0 else PI)
		var thigh_angle := swing * sin(local_phase)
		var knee_angle := deg_to_rad(knee_lift_degrees * (1.0 + 0.45 * run)) * pow(maxf(0.0, cos(local_phase - 0.25)), 1.6) + deg_to_rad(6.0)
		var thigh_rotation := Quaternion(swing_axis, thigh_angle) * Quaternion(Vector3.UP, yaw * 0.6)
		var knee_axis := thigh_rotation * lateral
		var knee_rotation := Quaternion(knee_axis, knee_angle)
		var push_off := deg_to_rad(16.0) * maxf(0.0, -sin(local_phase)) * maxf(0.0, -cos(local_phase))
		var level := (thigh_rotation * knee_rotation).inverse().slerp(Quaternion.IDENTITY, 0.2)
		var foot_rotation := Quaternion(knee_axis, push_off) * level
		_place_leg(skeleton, hips_global, bones, [thigh_rotation, knee_rotation, foot_rotation])


# Rebuild thigh, shin and foot from rest offsets with skeleton-space rotations,
# then blend the local result into the authored pose by the gait weight.
func _place_leg(skeleton: Skeleton3D, hips_global: Transform3D, bones: Array, rotations: Array) -> void:
	var parent_global := hips_global
	var accumulated := Quaternion.IDENTITY
	for index in 3:
		var bone: int = bones[index]
		var rest := skeleton.get_bone_rest(bone)
		var start := parent_global * rest
		accumulated = (rotations[index] as Quaternion) * accumulated
		var rest_global_basis := _rest_global_basis(skeleton, bone)
		var wanted := Transform3D(Basis(accumulated) * rest_global_basis, start.origin)
		var local := parent_global.affine_inverse() * wanted
		var current := skeleton.get_bone_pose_rotation(bone)
		var target := local.basis.get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(bone, current.slerp(target, weight))
		parent_global = parent_global * Transform3D(Basis(current.slerp(target, weight)), rest.origin)


func _rest_global_basis(skeleton: Skeleton3D, bone: int) -> Basis:
	return skeleton.get_bone_global_rest(bone).basis.orthonormalized()


func _parent_basis_inverse(skeleton: Skeleton3D, bone: int) -> Basis:
	var parent := skeleton.get_bone_parent(bone)
	if parent < 0:
		return Basis.IDENTITY
	return skeleton.get_bone_global_pose(parent).basis.inverse()


static func _crossed(before: float, after: float, mark: float) -> bool:
	if after >= before:
		return before < mark and after >= mark
	return before < mark or after >= mark


func _resolve_bones(skeleton: Skeleton3D) -> bool:
	for name: String in HIPS_NAMES:
		_hips = skeleton.find_bone(name)
		if _hips >= 0:
			break
	if _hips < 0:
		return false
	_legs.clear()
	for prefixes: Array in SIDE_PREFIXES:
		var thigh := _find(skeleton, prefixes, THIGH_NAMES)
		var shin := _find(skeleton, prefixes, SHIN_NAMES)
		var foot := _find(skeleton, prefixes, FOOT_NAMES)
		if thigh < 0 or shin < 0 or foot < 0:
			return false
		_legs.append([thigh, shin, foot])
	var left: Array = _legs[0]
	_leg_length = skeleton.get_bone_global_rest(left[0]).origin.distance_to(skeleton.get_bone_global_rest(left[2]).origin)
	return true


func _find(skeleton: Skeleton3D, prefixes: Array, names: Array) -> int:
	for prefix: String in prefixes:
		for name: String in names:
			for candidate in [prefix + name, "mixamorig:" + prefix + name]:
				var index := skeleton.find_bone(candidate)
				if index >= 0:
					return index
	return -1
