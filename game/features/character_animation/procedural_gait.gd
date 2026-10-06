extends SkeletonModifier3D
## Speed-synchronised leg gait layered over authored upper-body clips
## (ADR-0016). The legs are rebuilt from the rest pose every frame along
## walk/run curves (heel strike, loading, push-off, swing): thighs swing along
## the actual movement direction and are tucked under the hips (the rest pose
## stands with splayed legs), the sole rolls heel-to-toe and the hips ride on
## the supporting leg. Cadence and stride
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
var max_leg_yaw := 45.0
## Extra hips rise in the flight phase of a run, as a fraction of leg length.
var flight_lift := 0.025

# Gait curves over one cycle of a leg, u = 0 at its heel strike (stance ends
# near 0.6 when walking, 0.38 when running). Thigh values are fractions of the
# stride swing, knee and sole values degrees.
const WALK_THIGH := [[0.0, 1.0], [0.15, 0.7], [0.5, -0.8], [0.62, -0.55], [0.8, 0.75], [0.9, 1.05]]
const WALK_KNEE := [[0.0, 4.0], [0.12, 16.0], [0.38, 4.0], [0.55, 30.0], [0.7, 58.0], [0.84, 26.0], [0.94, 2.0]]
const WALK_SOLE := [[0.0, -14.0], [0.1, 0.0], [0.42, 0.0], [0.6, 32.0], [0.72, 12.0], [0.86, -4.0], [0.95, -14.0]]
const RUN_THIGH := [[0.0, 0.75], [0.16, 0.1], [0.36, -0.8], [0.5, -0.4], [0.7, 0.9], [0.86, 1.0]]
const RUN_KNEE := [[0.0, 22.0], [0.12, 38.0], [0.32, 18.0], [0.42, 48.0], [0.56, 92.0], [0.7, 76.0], [0.86, 36.0]]
const RUN_SOLE := [[0.0, -6.0], [0.14, 0.0], [0.34, 40.0], [0.46, 28.0], [0.66, 8.0], [0.88, -10.0]]

var phase := 0.0
var weight := 0.0
var _hips := -1
var _legs: Array = [] # [[thigh, shin, foot], ...] left first
var _leg_length := 0.9
var _thigh_length := 0.45
var _shin_length := 0.45
var _splay := [0.0, 0.0] # rest outward lean of each leg, radians, signed for roll_axis
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
		# A foot is planted at its heel strike (cycle position 0).
		for side in 2:
			var plant := PI * float(side)
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
	var roll_axis := leg_yaw * Vector3.BACK
	var angles := _leg_targets(swing, run)
	# The longer (supporting) leg carries the body; runs lift it in flight.
	var bob := (_thigh_length + _shin_length - float(angles[2])) * weight
	bob -= flight_lift * run * _leg_length * maxf(0.0, sin(2.0 * phase - 0.6)) * weight
	var hips_pose := skeleton.get_bone_pose_position(_hips)
	skeleton.set_bone_pose_position(_hips, hips_pose + _parent_basis_inverse(skeleton, _hips) * Vector3(0.0, -bob, 0.0))
	var hips_global := skeleton.get_bone_global_pose(_hips)
	for side in 2:
		var bones: Array = _legs[side]
		var leg_angle: Array = angles[side]
		# Bring the foot in under the hip: rest poses stand with splayed legs.
		var tuck := -float(_splay[side]) * (1.0 + 0.1 * run)
		var thigh_rotation := Quaternion(swing_axis, leg_angle[0]) * Quaternion(roll_axis, tuck) * Quaternion(Vector3.UP, yaw * 0.6)
		var knee_axis := thigh_rotation * lateral
		var knee_rotation := Quaternion(knee_axis, leg_angle[1])
		var level := (thigh_rotation * knee_rotation).inverse()
		var foot_rotation := Quaternion(lateral, leg_angle[2]) * level
		_place_leg(skeleton, hips_global, bones, [thigh_rotation, knee_rotation, foot_rotation])


# [left, right, reach]: each leg's [thigh, knee, sole] radians at the current
# phase and the vertical reach of the longer leg.
func _leg_targets(swing: float, run: float) -> Array:
	var targets := []
	var reach := 0.0
	for side in 2:
		var leg := leg_angles(fposmod(phase / TAU + 0.5 * float(side), 1.0), run)
		var thigh_angle := swing * leg.x
		var knee_angle := deg_to_rad(leg.y)
		targets.append([thigh_angle, knee_angle, deg_to_rad(leg.z)])
		reach = maxf(reach, _thigh_length * cos(thigh_angle) + _shin_length * cos(thigh_angle - knee_angle))
	targets.append(reach)
	return targets


## Leg angles at cycle position u (0 = this foot's heel strike) blended from
## walk to run: x = thigh swing as a fraction of the stride swing (+ forward),
## y = knee flexion degrees, z = sole pitch degrees (+ toe down).
static func leg_angles(u: float, run: float) -> Vector3:
	var walk := Vector3(_cycle(u, WALK_THIGH), _cycle(u, WALK_KNEE), _cycle(u, WALK_SOLE))
	var sprint := Vector3(_cycle(u, RUN_THIGH), _cycle(u, RUN_KNEE), _cycle(u, RUN_SOLE))
	return walk.lerp(sprint, run)


## Periodic Catmull-Rom curve through [u, value] keys sorted by u in [0, 1).
static func _cycle(u: float, keys: Array) -> float:
	var count := keys.size()
	var t := fposmod(u, 1.0)
	var index := count - 1
	for i in count:
		if float(keys[i][0]) > t:
			index = i - 1
			break
	if index < 0:
		index = count - 1
	var start := float(keys[index][0])
	var finish := float(keys[(index + 1) % count][0])
	if finish <= start:
		finish += 1.0
	if t < start:
		t += 1.0
	var k := (t - start) / maxf(finish - start, 0.0001)
	var p0 := float(keys[(index - 1 + count) % count][1])
	var p1 := float(keys[index][1])
	var p2 := float(keys[(index + 1) % count][1])
	var p3 := float(keys[(index + 2) % count][1])
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * k + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * k * k + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * k * k * k)


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
	for bone_name: String in HIPS_NAMES:
		_hips = skeleton.find_bone(bone_name)
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
	_thigh_length = skeleton.get_bone_global_rest(left[0]).origin.distance_to(skeleton.get_bone_global_rest(left[1]).origin)
	_shin_length = skeleton.get_bone_global_rest(left[1]).origin.distance_to(skeleton.get_bone_global_rest(left[2]).origin)
	for side in 2:
		var bones: Array = _legs[side]
		var hip := skeleton.get_bone_global_rest(bones[0]).origin
		var ankle := skeleton.get_bone_global_rest(bones[2]).origin
		# Keep a narrow natural step width: the ankle ends up a little outside the hip line.
		var target_x := hip.x * 0.65
		_splay[side] = atan2(ankle.x - target_x, hip.y - ankle.y)
	return true


func _find(skeleton: Skeleton3D, prefixes: Array, names: Array) -> int:
	for prefix: String in prefixes:
		for bone_name: String in names:
			for candidate in [prefix + bone_name, "mixamorig:" + prefix + bone_name]:
				var index := skeleton.find_bone(candidate)
				if index >= 0:
					return index
	return -1
