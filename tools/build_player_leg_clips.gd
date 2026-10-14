extends SceneTree
## Retargets the Mixamo run/dodge FBX clips onto the player's skeleton, legs and
## hips only (ADR-0044). Arms, shoulders and spine are never keyed, so the
## weapon holds stay exactly as authored.
##
## Run after an editor import of models/objects/characters/player_legs/*.fbx:
##   godot --headless --path . --script res://tools/build_player_leg_clips.gd
##
## Writes models/objects/characters/player_legs/player_leg_clips.res, an
## AnimationLibrary of clips keyed "Skeleton3D:<player bone>" with rotation
## tracks for the leg bones and position + rotation for the hips.
##
## Method: for every leg bone the Mixamo world-space turn away from its rest
## pose is applied to the player's rest pose, then the bone is aimed along the
## Mixamo bone direction, so the legs take the animated pose whatever the rest
## splay of the player mesh. Hips height follows the Mixamo hips scaled by the
## leg-length ratio. The missing forward-right run is the forward-left clip
## mirrored across the body's mid-plane.

const PLAYER := preload("res://models/objects/characters/soldier_animated.glb")
const SOURCE_DIR := "res://models/objects/characters/player_legs/"
const OUTPUT := "res://models/objects/characters/player_legs/player_leg_clips.res"
const FPS := 30.0
const MIRROR := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
const SUFFIXES := ["UpLeg", "Leg", "Foot", "ToeBase"]
# Player bone, Mixamo child that gives its direction ("" = no direction fix).
const CHILD := {"UpLeg": "Leg", "Leg": "Foot", "Foot": "ToeBase", "ToeBase": "ToeEnd"}
# name, source FBX, mirror, loop, in place (no root travel), trim seconds (-1 = whole clip)
const CLIPS := [
	["Run_Forward", "Run_Forward", false, true, false, -1.0],
	["Run_Forward_Left", "Run_Forward_Left", false, true, false, -1.0],
	["Run_Left", "Run_Left", false, true, false, -1.0],
	["Run_Backward_Left", "Run_Backward_Left", false, true, false, -1.0],
	["Run_Backward", "Run_Backward", false, true, false, -1.0],
	["Run_Backward_Right", "Run_Backward_Right", false, true, false, -1.0],
	["Run_Right", "Run_Right", false, true, false, -1.0],
	["Run_Forward_Right", "Run_Forward_Left", true, true, false, -1.0],
	["Dodge_Roll", "Running_Dive_Roll", false, false, true, 1.75],
	["Dodge_Strafe_Right", "Run_Strafing_Jump", false, false, true, -1.0],
	["Dodge_Strafe_Left", "Left_Strafe_Jump", false, false, true, -1.0],
]

var _player: Skeleton3D
var _scale := 1.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var model := PLAYER.instantiate()
	root.add_child(model)
	_player = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var library := AnimationLibrary.new()
	var reference: Array[float] = []
	for entry: Array in CLIPS:
		var animation := _bake(entry)
		if animation == null:
			quit(1)
			return
		if entry[3]:
			reference = _align_cycle(animation, reference)
		library.add_animation(entry[0], animation)
		print("%s: %.3fs, %d tracks, ref %.2f m/s toward %.0f deg, plants L %.2f R %.2f" % [entry[0], animation.length, animation.get_track_count(), float(animation.get_meta("ref_speed", 0.0)), float(animation.get_meta("travel_angle", 0.0)), float(animation.get_meta("plant_left", 0.0)), float(animation.get_meta("plant_right", 0.0))])
	for clip_name in library.get_animation_list():
		for key in ["foot_left", "foot_right", "frames"]:
			(library.get_animation(clip_name) as Animation).remove_meta(key)
	var error := ResourceSaver.save(library, OUTPUT)
	print("saved ", OUTPUT, " -> ", error)
	quit(0 if error == OK else 1)


func _bake(entry: Array) -> Animation:
	var packed := load(SOURCE_DIR + entry[1] + ".fbx") as PackedScene
	if packed == null:
		push_error("Missing " + entry[1])
		return null
	var instance := packed.instantiate()
	root.add_child(instance)
	var source := instance.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var player_source := instance.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var clip := player_source.get_animation(player_source.get_animation_list()[0])
	_scale = _leg_length(_player, "") / _leg_length(source, "mixamorig_")
	var length: float = clip.length if float(entry[5]) < 0.0 else minf(clip.length, float(entry[5]))
	var frames := int(round(length * FPS))
	var loop: bool = entry[3]
	var in_place: bool = entry[4]
	var mirror: bool = entry[2]
	var count := frames if loop else frames + 1
	var bones: Array[String] = ["Hips"]
	for side in ["Left", "Right"]:
		for suffix in SUFFIXES:
			bones.append(side + suffix)
	var rotations := {}
	var hips_positions: Array[Vector3] = []
	var feet := {"Left": [], "Right": []}
	for bone in bones:
		rotations[bone] = []
	for frame in count:
		_pose_source(source, clip, float(frame) / FPS)
		var poses := _retarget(source, mirror)
		for bone in bones:
			rotations[bone].append(poses[bone])
		hips_positions.append(poses["HipsPosition"])
		for side in ["Left", "Right"]:
			feet[side].append(poses[side + "FootWorld"])
	instance.queue_free()
	var travel := Vector3.ZERO
	if not in_place:
		for position in hips_positions:
			travel += position
		travel /= float(count)
	var rest_hips := _player.get_bone_rest(_player.find_bone("Hips")).origin
	var animation := Animation.new()
	animation.length = float(count if loop else frames) / FPS
	animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	animation.step = 1.0 / FPS
	for bone in bones:
		var path := NodePath("Skeleton3D:" + bone)
		var rotation_track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(rotation_track, path)
		for frame in count:
			animation.rotation_track_insert_key(rotation_track, float(frame) / FPS, rotations[bone][frame])
		if bone == "Hips":
			var position_track := animation.add_track(Animation.TYPE_POSITION_3D)
			animation.track_set_path(position_track, path)
			for frame in count:
				var position: Vector3 = hips_positions[frame]
				# In-place clips drop all horizontal travel; run cycles keep only the sway around their mean.
				position.x = position.x - travel.x if not in_place else 0.0
				position.z = position.z - travel.z if not in_place else 0.0
				animation.position_track_insert_key(position_track, float(frame) / FPS, rest_hips + position)
	if loop:
		var travel_velocity := _stance_velocity(feet, hips_positions, count)
		animation.set_meta("ref_speed", travel_velocity.length())
		animation.set_meta("travel_angle", rad_to_deg(atan2(travel_velocity.x, travel_velocity.y)))
		animation.set_meta("plant_left", _plant_phase(feet["Left"], count))
		animation.set_meta("plant_right", _plant_phase(feet["Right"], count))
		animation.set_meta("frames", count)
		animation.set_meta("foot_left", _heights(feet["Left"]))
		animation.set_meta("foot_right", _heights(feet["Right"]))
	return animation


func _leg_length(skeleton: Skeleton3D, prefix: String) -> float:
	var hip := skeleton.get_bone_global_rest(skeleton.find_bone(prefix + "LeftUpLeg")).origin
	var ankle := skeleton.get_bone_global_rest(skeleton.find_bone(prefix + "LeftFoot")).origin
	return hip.distance_to(ankle)


func _pose_source(source: Skeleton3D, clip: Animation, time: float) -> void:
	source.reset_bone_poses()
	for track in clip.get_track_count():
		var name := String(clip.track_get_path(track).get_concatenated_subnames())
		var bone := source.find_bone(name)
		if bone < 0:
			continue
		match clip.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				source.set_bone_pose_rotation(bone, clip.rotation_track_interpolate(track, time))
			Animation.TYPE_POSITION_3D:
				source.set_bone_pose_position(bone, clip.position_track_interpolate(track, time))


# Player-space local rotations (and hips position offset) for the posed source.
func _retarget(source: Skeleton3D, mirror: bool) -> Dictionary:
	var result := {}
	var globals := {} # new player global bases by bone name
	var origins := {}
	var hips_name := "Hips"
	var hips_source := source.find_bone("mixamorig_Hips")
	var hips_delta := _delta(source, hips_source)
	if mirror:
		hips_delta = MIRROR * hips_delta * MIRROR
	var hips_basis := hips_delta * _player.get_bone_global_rest(_player.find_bone(hips_name)).basis.orthonormalized()
	globals[hips_name] = hips_basis
	var root_basis := _player.get_bone_global_rest(_player.get_bone_parent(_player.find_bone(hips_name))).basis.orthonormalized()
	result[hips_name] = (root_basis.inverse() * hips_basis).get_rotation_quaternion()
	var hips_move := source.get_bone_global_pose(hips_source).origin - source.get_bone_global_rest(hips_source).origin
	if mirror:
		hips_move.x = -hips_move.x
	result["HipsPosition"] = hips_move * _scale
	for side in ["Left", "Right"]:
		var source_side: String = ("Right" if side == "Left" else "Left") if mirror else side
		var parent_basis := hips_basis
		for suffix in SUFFIXES:
			var bone: String = side + suffix
			var player_index := _player.find_bone(bone)
			var source_index := source.find_bone("mixamorig_" + source_side + suffix)
			var delta := _delta(source, source_index)
			if mirror:
				delta = MIRROR * delta * MIRROR
			var rest := _player.get_bone_global_rest(player_index)
			var wanted := delta * rest.basis.orthonormalized()
			var child_name: String = CHILD[suffix]
			var child_source := source.find_bone("mixamorig_" + source_side + ("Toe_End" if child_name == "ToeEnd" else child_name))
			var child_player := _player.find_bone(side + child_name)
			if child_source >= 0 and child_player >= 0:
				var target := source.get_bone_global_pose(child_source).origin - source.get_bone_global_pose(source_index).origin
				if mirror:
					target.x = -target.x
				var current := (_player.get_bone_global_rest(child_player).origin - rest.origin).normalized()
				var turned := (delta * current).normalized()
				target = target.normalized()
				if target.length() > 0.5 and turned.dot(target) < 0.99999:
					wanted = Basis(Quaternion(turned, target)) * wanted
			var local := parent_basis.inverse() * wanted
			result[bone] = local.orthonormalized().get_rotation_quaternion()
			globals[bone] = wanted
			parent_basis = wanted
		# World height of the foot relative to the hips, for stance detection.
		var foot_global := source.get_bone_global_pose(source.find_bone("mixamorig_" + source_side + "Foot")).origin
		if mirror:
			foot_global.x = -foot_global.x
		result[side + "FootWorld"] = foot_global * _scale
	return result


func _delta(source: Skeleton3D, bone: int) -> Basis:
	var animated := source.get_bone_global_pose(bone).basis.orthonormalized()
	var rest := source.get_bone_global_rest(bone).basis.orthonormalized()
	return animated * rest.inverse()


# Velocity (x left, y forward, m/s) at which the planted foot does not slide:
# its backward travel relative to the hips while it is at its lowest.
func _stance_velocity(feet: Dictionary, hips: Array[Vector3], count: int) -> Vector2:
	var speeds: Array[Vector2] = []
	for side: String in feet:
		var lowest := INF
		for frame in count:
			lowest = minf(lowest, (feet[side][frame] as Vector3).y)
		for frame in count:
			var next := (frame + 1) % count
			var here: Vector3 = feet[side][frame]
			var there: Vector3 = feet[side][next]
			if here.y < lowest + 0.035 and there.y < lowest + 0.035:
				var step := Vector2(there.x - here.x - (hips[next].x - hips[frame].x), there.z - here.z - (hips[next].z - hips[frame].z)) * FPS
				speeds.append(-step)
	if speeds.is_empty():
		return Vector2.ZERO
	var total := Vector2.ZERO
	for value in speeds:
		total += value
	return total / float(speeds.size())


func _heights(foot: Array) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	for position: Vector3 in foot:
		heights.append(position.y)
	return heights


# Cycle position (0..1) where a foot comes down: the first frame of its stance.
func _plant_phase(foot: Array, count: int) -> float:
	var lowest := INF
	var highest := -INF
	for position: Vector3 in foot:
		lowest = minf(lowest, position.y)
		highest = maxf(highest, position.y)
	var threshold := lowest + (highest - lowest) * 0.25
	for frame in count:
		var previous: Vector3 = foot[(frame - 1 + count) % count]
		if (foot[frame] as Vector3).y <= threshold and previous.y > threshold:
			return float(frame) / float(count)
	return 0.0


# Rotates the cycle so both feet lift and land at the same phase as the first
# run (compared by foot height, which does not depend on the run direction).
func _align_cycle(animation: Animation, reference: Array[float]) -> Array[float]:
	var curve := _foot_curve(animation)
	if reference.is_empty():
		return curve
	var count := animation.get_meta("frames") as int
	var best := 0
	var best_error := INF
	for shift in count:
		var error := 0.0
		for index in reference.size():
			var phase := float(index) / float(reference.size())
			var sample := curve[int(round(fposmod(phase * count + float(shift), float(count)))) % count]
			error += absf(sample - reference[index])
		if error < best_error:
			best_error = error
			best = shift
	if best != 0:
		_shift_cycle(animation, best)
		for key in ["plant_left", "plant_right"]:
			animation.set_meta(key, fposmod(float(animation.get_meta(key)) - float(best) / float(count), 1.0))
		print("  phase-aligned by %d frames" % best)
	return reference


# Left foot height minus right foot height over the cycle, one value per frame.
func _foot_curve(animation: Animation) -> Array[float]:
	var left: PackedFloat32Array = animation.get_meta("foot_left")
	var right: PackedFloat32Array = animation.get_meta("foot_right")
	var curve: Array[float] = []
	for index in left.size():
		curve.append(left[index] - right[index])
	return curve


func _shift_cycle(animation: Animation, shift: int) -> void:
	for track in animation.get_track_count():
		var keys := animation.track_get_key_count(track)
		var values: Array = []
		for index in keys:
			values.append(animation.track_get_key_value(track, index))
		for index in keys:
			animation.track_set_key_value(track, index, values[(index + shift) % keys])
