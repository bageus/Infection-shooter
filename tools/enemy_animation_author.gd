extends RefCounted
## Build-time author of enemy animation clips (ADR-0016).
##
## Clips are described as poses in a small parameter space (lean, twist, leg
## swing, knee, shoulder flex/abduction, elbow ...). Parameters are degrees in
## the model frame: +Z is the front, +X is the character's left, rest bone
## bases are identity. Arms are first aligned to a hanging pose so the same
## clips fit T-pose (zombie/mutant) and A-pose (auto-rigged) skeletons.
##
## Used by tools/build_enemy_rigs.gd; the game only plays the baked clips.

const FPS := 30.0
const DEATH_POSES := preload("res://tools/enemy_death_poses.gd")
const SIDES := {"L_": 1.0, "R_": -1.0}
const BONES := [
	"Hips", "Spine", "Chest", "Neck", "Head",
	"L_Shoulder", "L_UpperArm", "L_Forearm", "L_Hand",
	"R_Shoulder", "R_UpperArm", "R_Forearm", "R_Hand",
	"L_Thigh", "L_Shin", "L_Foot", "L_Toe",
	"R_Thigh", "R_Shin", "R_Foot", "R_Toe",
]
const SIDED_PARAMS := ["swing", "knee", "ankle", "sole", "abd_leg", "flex", "abd", "elbow", "wrist", "shrug", "protract"]
const MIRRORED_PARAMS := ["twist", "side_bend", "hips_roll", "hips_x", "hips_yaw", "head_tilt", "head_turn"]

var skeleton: Skeleton3D
var _bone := {}
var _rest_local := {}
var _arm_align := {}
var _elbow_axis := {}
var _wrist_axis := {}
var hips_height := 1.0 # Hips joint above the floor, model units.
var leg_length := 0.9
var thigh_length := 0.45
var shin_length := 0.45
var _splay := {}
var _hip_width := {}


func setup(target: Skeleton3D) -> void:
	skeleton = target
	for index in skeleton.get_bone_count():
		_bone[skeleton.get_bone_name(index)] = index
		_rest_local[skeleton.get_bone_name(index)] = skeleton.get_bone_rest(index)
	var floor_y := INF
	for index in skeleton.get_bone_count():
		floor_y = minf(floor_y, skeleton.get_bone_global_rest(index).origin.y)
	if _bone.has("L_Toe"):
		floor_y = minf(floor_y, _global("L_Toe").y - 0.05)
	hips_height = _global("Hips").y - floor_y
	leg_length = _global("L_Thigh").distance_to(_global("L_Foot"))
	thigh_length = _global("L_Thigh").distance_to(_global("L_Shin"))
	shin_length = _global("L_Shin").distance_to(_global("L_Foot"))
	for prefix: String in SIDES:
		var side: float = SIDES[prefix]
		var hip := _global(prefix + "Thigh")
		var ankle := _global(prefix + "Foot")
		# Outward lean of the rest leg in degrees (auto-rigs stand in an A-frame).
		_splay[prefix] = rad_to_deg(atan2(side * (ankle.x - hip.x), hip.y - ankle.y))
		_hip_width[prefix] = side * hip.x
	for prefix: String in SIDES:
		var side: float = SIDES[prefix]
		var arm := (_global(prefix + "Forearm") - _global(prefix + "UpperArm")).normalized()
		var hanging := arm
		# T-posed arms are first lowered to a relaxed hang.
		if arm.angle_to(Vector3.DOWN) > deg_to_rad(50.0):
			hanging = Vector3(side * sin(deg_to_rad(14.0)), -cos(deg_to_rad(14.0)), 0.0)
		_arm_align[prefix] = Quaternion(arm, hanging) if not arm.is_equal_approx(hanging) else Quaternion.IDENTITY
		var forearm := (_global(prefix + "Hand") - _global(prefix + "Forearm")).normalized()
		_elbow_axis[prefix] = _flex_axis(forearm)
		_wrist_axis[prefix] = _flex_axis(forearm)


const RUN_FLIGHT := 1.25 # running strides cover more ground than the leg arc


# Cycles per second that move the feet at the style's gameplay speeds.
func pace(style: Dictionary) -> Dictionary:
	var scale := float(style.get("scale", 1.0))
	var walk_cycle := 4.0 * leg_length * scale * sin(deg_to_rad(float(style.walk_swing)))
	var run_cycle := RUN_FLIGHT * 4.0 * leg_length * scale * sin(deg_to_rad(float(style.run_swing)))
	var walk_hz := clampf(float(style.walk_mps) / walk_cycle, 0.6, 1.9)
	var run_hz := clampf(float(style.run_mps) / run_cycle, 0.9, 2.4)
	return {"walk_hz": walk_hz, "run_hz": run_hz, "walk_mps": walk_hz * walk_cycle, "run_mps": run_hz * run_cycle}


# Builds the humanoid clip library. style keys: scale, walk_mps, run_mps, walk_swing,
# run_swing, lean, reach, heavy (0..1), attack_seconds, death_seconds,
# slam (bool), slam_seconds.
func build_humanoid_library(source_style: Dictionary) -> AnimationLibrary:
	var style := source_style.duplicate()
	style.merge(pace(style), true)
	var library := AnimationLibrary.new()
	library.add_animation(&"Idle", _bake(func(t: float) -> Dictionary: return _idle(t, style), 3.0, true))
	library.add_animation(&"Walk", _bake(func(t: float) -> Dictionary: return _walk(t, style), 1.0 / float(style.walk_hz), true))
	library.add_animation(&"Run", _bake(func(t: float) -> Dictionary: return _run(t, style), 1.0 / float(style.run_hz), true))
	var attack_length := float(style.attack_seconds)
	library.add_animation(&"AttackRight", _bake(func(t: float) -> Dictionary: return _keyed(t / attack_length, _attack_keys(style), style), attack_length, false))
	library.add_animation(&"AttackLeft", _bake(func(t: float) -> Dictionary: return _mirror(_keyed(t / attack_length, _attack_keys(style), style)), attack_length, false))
	var death_length := float(style.death_seconds)
	library.add_animation(&"Death", _bake(func(t: float) -> Dictionary: return _keyed(t / death_length, _death_keys(style), style), death_length, false))
	# Directional deaths (ADR-0034): a forward fall and a thrown-back fall.
	var forward_keys := DEATH_POSES.forward_keys(_stance(style), hips_height)
	library.add_animation(&"DeathForward", _bake(func(t: float) -> Dictionary: return _keyed(t / death_length, forward_keys, style), death_length, false))
	var back_length := death_length * 0.85
	var back_keys := DEATH_POSES.back_keys(_stance(style), hips_height)
	library.add_animation(&"DeathBack", _bake(func(t: float) -> Dictionary: return _keyed(t / back_length, back_keys, style), back_length, false))
	if bool(style.get("slam", false)):
		var slam_length := float(style.slam_seconds)
		library.add_animation(&"Slam", _bake(func(t: float) -> Dictionary: return _keyed(t / slam_length, _slam_keys(style), style), slam_length, false))
	return library


# ---------------------------------------------------------------- clips

func _stance(style: Dictionary) -> Dictionary:
	var heavy := float(style.heavy)
	return {
		"lean": 7.0 + 5.0 * heavy, "neck": 6.0, "head": -4.0,
		"L_flex": 8.0, "R_flex": 12.0, "L_elbow": 18.0, "R_elbow": 24.0,
		"L_abd": 2.0 + 4.0 * heavy, "R_abd": 2.0 + 4.0 * heavy,
		"L_knee": 6.0 + 6.0 * heavy, "R_knee": 6.0 + 6.0 * heavy,
		"L_swing": 3.0 + 3.0 * heavy, "R_swing": 3.0 + 3.0 * heavy,
		"L_abd_leg": 2.0 * heavy, "R_abd_leg": 2.0 * heavy,
		"hips_y": -0.02 * hips_height * (1.0 + heavy),
		"head_tilt": 6.0,
	}


func _idle(t: float, style: Dictionary) -> Dictionary:
	var p := _stance(style)
	var breath := sin(t / 3.0 * TAU)
	var sway := sin(t / 3.0 * TAU + 1.1)
	p.lean += 1.5 * breath
	p.chest_pitch = -1.5 * breath
	p.L_shrug = 2.0 * breath
	p.R_shrug = 2.0 * breath
	p.head_turn = 7.0 * sin(t / 3.0 * TAU * 2.0 + 0.4)
	p.head_tilt = 6.0 + 3.0 * sway
	p.hips_x = 0.01 * hips_height * sway
	p.L_flex += 3.0 * sway
	p.R_flex -= 3.0 * sway
	return p


func _walk(t: float, style: Dictionary) -> Dictionary:
	var heavy := float(style.heavy)
	var phase := t * float(style.walk_hz) * TAU
	var amplitude := float(style.walk_swing)
	var p := _stance(style)
	# Heavy-footed shuffle: the hips sink into each step, the torso rolls over it.
	p.lean = 10.0 + 6.0 * heavy + 2.0 * cos(2.0 * phase)
	_gait(p, phase, amplitude, [WALK_THIGH, WALK_KNEE, WALK_SOLE], 1.0 + 0.2 * heavy, 0.07 + 0.14 * heavy, 0.02, 4.0)
	p.side_bend = 4.0 * cos(phase)
	# Loose arms hang a little forward and swing against the legs, lagging behind.
	var reach := float(style.reach)
	p.L_flex = 10.0 + 12.0 * reach - 18.0 * sin(phase - 0.5)
	p.R_flex = 16.0 + 16.0 * reach + 18.0 * sin(phase - 0.5)
	p.L_abd = 6.0 + 4.0 * heavy
	p.R_abd = 8.0 + 4.0 * heavy
	p.L_elbow = 20.0 + 10.0 * maxf(0.0, sin(phase - 0.5))
	p.R_elbow = 26.0 + 10.0 * maxf(0.0, -sin(phase - 0.5))
	p.L_wrist = 12.0
	p.R_wrist = 16.0
	p.twist = 7.0 * sin(phase)
	p.head_tilt = 7.0 + 4.0 * sin(phase)
	p.neck = 8.0
	p.head = -6.0 + 3.0 * cos(phase * 2.0 + 0.6)
	return p


func _run(t: float, style: Dictionary) -> Dictionary:
	var heavy := float(style.heavy)
	var phase := t * float(style.run_hz) * TAU
	var p := _stance(style)
	# Predator sprint: torso thrown forward, dipping on every landing, head up
	# and locked on the prey, legs driving long strides with a high heel kick.
	p.lean = float(style.lean) + 6.0 + 4.0 * cos(2.0 * phase - 0.8)
	_gait(p, phase, float(style.run_swing), [RUN_THIGH, RUN_KNEE, RUN_SOLE], 1.0 - 0.25 * heavy, 0.04 + 0.12 * heavy, 0.015, 12.0 - 4.0 * heavy)
	p.hips_y -= 0.03 * hips_height * (1.0 + heavy)
	p.hips_z = 0.03 * hips_height
	# Clawing arms pump against the legs, thrown forward to grab, never quite in step.
	var reach := 52.0 + 16.0 * float(style.reach)
	for prefix: String in SIDES:
		var side: float = SIDES[prefix]
		var lag := 0.0 if side > 0.0 else 0.06
		var u := fposmod(phase / TAU + (0.0 if side > 0.0 else 0.5) - lag, 1.0)
		var pump := -_cycle(u, RUN_THIGH) * (1.0 if side > 0.0 else 1.15)
		p[prefix + "flex"] = reach + 40.0 * pump
		p[prefix + "abd"] = 12.0 + 8.0 * maxf(0.0, -pump) + 4.0 * heavy
		p[prefix + "elbow"] = 52.0 - 26.0 * pump
		p[prefix + "wrist"] = -22.0 + 10.0 * pump
		p[prefix + "protract"] = 8.0 + 12.0 * maxf(0.0, pump)
		p[prefix + "shrug"] = 10.0 + 4.0 * heavy
	p.twist = -12.0 * sin(phase)
	p.side_bend = 3.0 * cos(phase)
	p.neck = 16.0
	p.head = -0.75 * (float(p.lean) + float(p.hips_pitch)) - 4.0 * cos(2.0 * phase - 0.8)
	p.head_turn = 4.0 * sin(3.0 * phase)
	p.head_tilt = 5.0 * sin(phase)
	return p


# Gait curves over one leg cycle, u = 0 at that foot's heel strike. Thigh
# values are fractions of the stride swing (+ forward), knee values degrees of
# flexion, sole values the foot's pitch in degrees (+ toe down).
const WALK_THIGH := [[0.0, 1.0], [0.15, 0.7], [0.5, -0.8], [0.62, -0.55], [0.8, 0.75], [0.9, 1.05]]
const WALK_KNEE := [[0.0, 4.0], [0.12, 18.0], [0.38, 5.0], [0.55, 30.0], [0.7, 60.0], [0.84, 26.0], [0.94, 2.0]]
const WALK_SOLE := [[0.0, -14.0], [0.1, 0.0], [0.42, 0.0], [0.6, 30.0], [0.72, 12.0], [0.86, -4.0], [0.95, -14.0]]
# Sprint: short stance (to 0.36), flight, heel kicked high, knee driven forward.
const RUN_THIGH := [[0.0, 0.7], [0.16, 0.05], [0.36, -0.85], [0.5, -0.45], [0.7, 0.95], [0.86, 1.0]]
const RUN_KNEE := [[0.0, 22.0], [0.12, 40.0], [0.32, 20.0], [0.42, 55.0], [0.56, 108.0], [0.7, 88.0], [0.86, 38.0]]
const RUN_SOLE := [[0.0, -6.0], [0.14, 0.0], [0.34, 42.0], [0.46, 30.0], [0.66, 8.0], [0.88, -10.0]]


# Alternating leg cycle. phase 0 = left heel strike, right heel strikes at PI
# (or a little later with `limp`). The feet are tucked under the body to
# `width` (fraction of hips height from the midline), the soles roll from heel
# to toe and the hips ride on the supporting leg.
func _gait(p: Dictionary, phase: float, amplitude: float, keys: Array, knee_scale: float, width: float, limp: float = 0.0, pitch: float = 0.0) -> void:
	var lowest := INF
	# The pelvis tips forward by `pitch`; thighs compensate so the legs keep their world arc.
	p.hips_pitch = pitch
	for prefix: String in SIDES:
		var offset := 0.0 if prefix == "L_" else 0.5 + limp
		var u := fposmod(phase / TAU + offset, 1.0)
		# A limping leg takes a shorter, later step.
		var favour := 1.0 - (3.0 * limp if prefix == "R_" else 0.0)
		var swing := amplitude * _cycle(u, keys[0]) * favour
		var knee := _cycle(u, keys[1]) * knee_scale
		p[prefix + "swing"] = swing + pitch
		p[prefix + "knee"] = knee
		p[prefix + "sole"] = _cycle(u, keys[2])
		# Lean the leg in so the ankle lands `width` from the midline.
		var lateral := rad_to_deg(atan2(width * hips_height - float(_hip_width[prefix]), leg_length))
		p[prefix + "abd_leg"] = lateral - float(_splay[prefix])
		var t := deg_to_rad(swing)
		var reach := thigh_length * cos(t) + shin_length * cos(t - deg_to_rad(knee))
		lowest = minf(lowest, thigh_length + shin_length - reach)
	# The supporting (longer) leg keeps its foot on the floor.
	p.hips_y = -lowest
	p.hips_x = -0.02 * hips_height * cos(phase)
	p.hips_yaw = -7.0 * sin(phase)
	p.hips_roll = -3.0 * cos(phase)


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


func _attack_keys(style: Dictionary) -> Array:
	var heavy := float(style.heavy)
	var stance := _stance(style)
	stance.lean += 4.0
	stance.L_flex = 28.0
	stance.R_flex = 34.0
	stance.L_elbow = 32.0
	stance.R_elbow = 36.0
	var windup := stance.duplicate()
	windup.merge({
		"twist": -28.0, "lean": 2.0, "side_bend": 6.0,
		"R_flex": 150.0, "R_abd": 42.0, "R_elbow": 95.0 - 40.0 * heavy, "R_wrist": -25.0, "R_shrug": 18.0, "R_protract": -12.0,
		"L_flex": 48.0, "L_abd": 6.0, "L_elbow": 48.0,
		"L_swing": 14.0, "L_knee": 14.0, "R_swing": -14.0, "R_knee": 10.0,
		"hips_y": -0.04 * hips_height, "hips_yaw": -10.0, "head": -10.0, "neck": 4.0,
	}, true)
	var strike := stance.duplicate()
	strike.merge({
		"twist": 22.0, "lean": 24.0 + 6.0 * heavy, "side_bend": -4.0,
		"R_flex": 82.0, "R_abd": 4.0, "R_elbow": 12.0, "R_wrist": 22.0, "R_shrug": 6.0, "R_protract": 18.0,
		"L_flex": 18.0, "L_abd": 10.0, "L_elbow": 34.0,
		"L_swing": 24.0, "L_knee": 28.0, "R_swing": -20.0, "R_knee": 14.0,
		"hips_y": -0.08 * hips_height, "hips_z": 0.06 * hips_height, "hips_yaw": 10.0, "head": -16.0, "neck": 12.0,
	}, true)
	var follow := strike.duplicate()
	follow.merge({"twist": 32.0, "lean": 27.0 + 6.0 * heavy, "R_flex": 36.0, "R_abd": -38.0, "R_elbow": 28.0, "R_wrist": 30.0, "R_protract": 10.0}, true)
	var settle := stance.duplicate()
	settle.merge({"twist": 10.0, "lean": 14.0, "R_flex": 30.0, "R_elbow": 34.0, "L_swing": 10.0, "L_knee": 14.0}, true)
	return [[0.0, stance], [0.36, windup], [0.40, windup], [0.47, strike], [0.58, follow], [0.78, settle], [1.0, stance]]


func _death_keys(style: Dictionary) -> Array:
	var stance := _stance(style)
	var recoil := stance.duplicate()
	recoil.merge({"lean": -16.0, "head": -28.0, "neck": -8.0, "L_flex": 42.0, "R_flex": 48.0, "L_abd": 28.0, "R_abd": 32.0, "L_elbow": 55.0, "R_elbow": 60.0, "hips_z": -0.03 * hips_height, "twist": 8.0}, true)
	var buckle := recoil.duplicate()
	buckle.merge({"L_knee": 70.0, "R_knee": 58.0, "L_swing": 32.0, "R_swing": 22.0, "hips_y": -0.38 * hips_height, "hips_pitch": -22.0, "lean": -6.0, "head": -12.0, "L_ankle": -20.0, "R_ankle": -16.0}, true)
	var lying := 0.13 * hips_height - hips_height
	var fall := buckle.duplicate()
	fall.merge({
		"hips_pitch": -88.0, "hips_y": lying, "hips_z": -0.42 * hips_height, "lean": 4.0, "head": 8.0, "neck": 6.0,
		"L_knee": 24.0, "R_knee": 34.0, "L_swing": 8.0, "R_swing": 14.0, "L_ankle": 10.0, "R_ankle": 18.0,
		"L_flex": -12.0, "R_flex": -6.0, "L_abd": 62.0, "R_abd": 74.0, "L_elbow": 26.0, "R_elbow": 18.0, "head_turn": 24.0, "twist": 4.0,
	}, true)
	var bounce := fall.duplicate()
	bounce.merge({"hips_pitch": -94.0, "hips_y": lying + 0.04 * hips_height, "L_abd": 74.0, "R_abd": 84.0}, true)
	var rest := fall.duplicate()
	rest.merge({"hips_pitch": -90.0, "head_turn": 30.0, "L_knee": 16.0, "R_knee": 28.0}, true)
	return [[0.0, stance], [0.14, recoil], [0.42, buckle], [0.7, fall], [0.82, bounce], [1.0, rest]]


func _slam_keys(style: Dictionary) -> Array:
	var stance := _stance(style)
	var raise := stance.duplicate()
	raise.merge({
		"lean": -14.0, "head": -22.0, "neck": -6.0, "hips_y": 0.03 * hips_height,
		"L_flex": 168.0, "R_flex": 168.0, "L_abd": 18.0, "R_abd": 18.0, "L_elbow": 50.0, "R_elbow": 50.0,
		"L_wrist": -30.0, "R_wrist": -30.0, "L_shrug": 22.0, "R_shrug": 22.0, "L_knee": 4.0, "R_knee": 4.0,
	}, true)
	var swing_down := raise.duplicate()
	swing_down.merge({"lean": 18.0, "L_flex": 120.0, "R_flex": 120.0, "L_elbow": 20.0, "R_elbow": 20.0, "head": -10.0}, true)
	var impact := stance.duplicate()
	impact.merge({
		"lean": 48.0, "neck": 14.0, "head": -30.0, "hips_y": -0.26 * hips_height, "hips_z": -0.05 * hips_height,
		"L_flex": 46.0, "R_flex": 46.0, "L_abd": 6.0, "R_abd": 6.0, "L_elbow": 8.0, "R_elbow": 8.0,
		"L_wrist": 30.0, "R_wrist": 30.0, "L_protract": 16.0, "R_protract": 16.0, "L_shrug": -6.0, "R_shrug": -6.0,
		"L_swing": 48.0, "R_swing": 40.0, "L_knee": 78.0, "R_knee": 70.0, "L_ankle": -24.0, "R_ankle": -22.0,
		"L_abd_leg": 10.0, "R_abd_leg": 10.0,
	}, true)
	var shudder := impact.duplicate()
	shudder.merge({"lean": 44.0, "hips_y": -0.23 * hips_height, "head": -24.0}, true)
	return [[0.0, stance], [0.40, raise], [0.46, raise], [0.52, swing_down], [0.56, impact], [0.64, shudder], [0.72, impact], [1.0, stance]]


# ---------------------------------------------------------------- pose maths

func _keyed(progress: float, keys: Array, _style: Dictionary) -> Dictionary:
	var u := clampf(progress, 0.0, 1.0)
	for index in range(1, keys.size()):
		var next: Array = keys[index]
		if u <= float(next[0]) or index == keys.size() - 1:
			var previous: Array = keys[index - 1]
			var span := maxf(float(next[0]) - float(previous[0]), 0.0001)
			var k := clampf((u - float(previous[0])) / span, 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k)
			return _blend(previous[1], next[1], k)
	return (keys[0] as Array)[1]


func _blend(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var out := {}
	for key in a:
		out[key] = lerpf(float(a[key]), float(b.get(key, 0.0)), k)
	for key in b:
		if not out.has(key):
			out[key] = lerpf(0.0, float(b[key]), k)
	return out


func _mirror(p: Dictionary) -> Dictionary:
	var out := p.duplicate()
	for name: String in SIDED_PARAMS:
		out["L_" + name] = p.get("R_" + name, 0.0)
		out["R_" + name] = p.get("L_" + name, 0.0)
	for name: String in MIRRORED_PARAMS:
		if p.has(name):
			out[name] = -float(p[name])
	return out


func _value(p: Dictionary, key: String) -> float:
	return deg_to_rad(float(p.get(key, 0.0)))


func pose_rotations(p: Dictionary) -> Dictionary:
	var q := {}
	q["Hips"] = Quaternion(Vector3.UP, _value(p, "hips_yaw")) * Quaternion(Vector3.RIGHT, _value(p, "hips_pitch")) * Quaternion(Vector3.BACK, _value(p, "hips_roll"))
	var lean := _value(p, "lean")
	var twist := _value(p, "twist")
	var bend := _value(p, "side_bend")
	q["Spine"] = Quaternion(Vector3.RIGHT, lean * 0.5) * Quaternion(Vector3.UP, twist * 0.45 - _value(p, "hips_yaw") * 0.7) * Quaternion(Vector3.BACK, bend * 0.5 - _value(p, "hips_roll"))
	q["Chest"] = Quaternion(Vector3.RIGHT, lean * 0.5 + _value(p, "chest_pitch")) * Quaternion(Vector3.UP, twist * 0.55) * Quaternion(Vector3.BACK, bend * 0.5)
	q["Neck"] = Quaternion(Vector3.RIGHT, _value(p, "neck"))
	q["Head"] = Quaternion(Vector3.UP, _value(p, "head_turn")) * Quaternion(Vector3.RIGHT, _value(p, "head")) * Quaternion(Vector3.BACK, _value(p, "head_tilt"))
	for prefix: String in SIDES:
		var side: float = SIDES[prefix]
		q[prefix + "Shoulder"] = Quaternion(Vector3.UP, -side * _value(p, prefix + "protract")) * Quaternion(Vector3.BACK, side * _value(p, prefix + "shrug"))
		q[prefix + "UpperArm"] = Quaternion(Vector3.RIGHT, -_value(p, prefix + "flex")) * Quaternion(Vector3.BACK, side * _value(p, prefix + "abd")) * (_arm_align[prefix] as Quaternion)
		q[prefix + "Forearm"] = Quaternion(_elbow_axis[prefix], _value(p, prefix + "elbow"))
		q[prefix + "Hand"] = Quaternion(_wrist_axis[prefix], _value(p, prefix + "wrist"))
		q[prefix + "Thigh"] = Quaternion(Vector3.RIGHT, -_value(p, prefix + "swing")) * Quaternion(Vector3.BACK, side * _value(p, prefix + "abd_leg"))
		q[prefix + "Shin"] = Quaternion(Vector3.RIGHT, _value(p, prefix + "knee"))
		if p.has(prefix + "sole"):
			# Gait clips give the sole's pitch in the model frame: undo the hips,
			# thigh and knee rotations so the foot rolls flat heel-to-toe.
			var leg := (q["Hips"] as Quaternion) * (q[prefix + "Thigh"] as Quaternion) * (q[prefix + "Shin"] as Quaternion)
			q[prefix + "Foot"] = leg.inverse() * Quaternion(Vector3.RIGHT, _value(p, prefix + "sole"))
			q[prefix + "Toe"] = Quaternion(Vector3.RIGHT, -0.7 * maxf(0.0, _value(p, prefix + "sole")))
		else:
			q[prefix + "Foot"] = Quaternion(Vector3.RIGHT, _value(p, prefix + "ankle"))
			q[prefix + "Toe"] = Quaternion(Vector3.RIGHT, -0.5 * maxf(0.0, _value(p, prefix + "ankle")))
	return q


func hips_offset(p: Dictionary) -> Vector3:
	return Vector3(float(p.get("hips_x", 0.0)), float(p.get("hips_y", 0.0)), float(p.get("hips_z", 0.0)))


func _bake(sampler: Callable, length: float, looping: bool) -> Animation:
	var animation := Animation.new()
	animation.length = length
	animation.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	var tracks := {}
	for bone: String in BONES:
		if not _bone.has(bone):
			continue
		var track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, NodePath("Skeleton3D:" + bone))
		tracks[bone] = track
	var hips_track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(hips_track, NodePath("Skeleton3D:Hips"))
	var frames := maxi(2, ceili(length * FPS))
	for frame in frames + 1:
		var time := minf(length, float(frame) / FPS)
		if looping and frame == frames:
			time = length
		var pose: Dictionary = sampler.call(fmod(time, length) if looping else time)
		var rotations := pose_rotations(pose)
		for bone: String in tracks:
			animation.rotation_track_insert_key(tracks[bone], time, (rotations[bone] as Quaternion).normalized())
		var rest: Transform3D = _rest_local["Hips"]
		animation.position_track_insert_key(hips_track, time, rest.origin + hips_offset(pose))
	return animation


func _global(bone: String) -> Vector3:
	return skeleton.get_bone_global_rest(_bone[bone]).origin


# Rotation axis that bends a limb segment pointing along `direction` toward the front.
static func _flex_axis(direction: Vector3) -> Vector3:
	var axis := direction.cross(Vector3.BACK)
	if axis.length_squared() < 0.0001:
		return Vector3.RIGHT
	return axis.normalized()
