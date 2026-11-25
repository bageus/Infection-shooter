extends SceneTree
## Retargets the Mixamo hero clips (turn in place, kick, deaths) onto the soldier skeleton.
##
## Run after an editor import of models/objects/characters/player_legs/*.fbx:
##   godot --headless --path . --script res://tools/build_hero_clips.gd
##
## Writes models/objects/characters/hero_extra_clips.res, an AnimationLibrary merged into the
## player's clips by the animation driver (`extra_clips`). Same method as build_hunger_clips.gd:
## per bone (parents first) the Mixamo world-space turn away from its rest pose is applied to the
## soldier rest pose, then the bone is aimed along the Mixamo bone direction, so the different rest
## poses do not matter. Fingers, backpack and sleeve are not keyed and follow their parents.
## Hips travel is scaled by the leg-length ratio; horizontal travel is removed (the game moves the
## hero), the height is kept so a fall ends lying on the floor.

const SOURCE_DIR := "res://models/objects/characters/player_legs/"
const OUTPUT := "res://models/objects/characters/hero_extra_clips.res"
const TRACK_ROOT := "Character_Rig/Skeleton3D:"
const FPS := 30.0
const PREFIX := "mixamorig_"
# Soldier bone, Mixamo bone, soldier child that gives the direction, Mixamo child.
const MAP := [
	["Hips", "Hips", "Spine", "Spine"],
	["Spine", "Spine", "Spine1", "Spine1"],
	["Spine1", "Spine1", "Spine2", "Spine2"],
	["Spine2", "Spine2", "Neck", "Neck"],
	["Neck", "Neck", "Head", "Head"],
	["Head", "Head", "", ""],
	["LeftShoulder", "LeftShoulder", "LeftArm", "LeftArm"],
	["LeftArm", "LeftArm", "LeftForeArm", "LeftForeArm"],
	["LeftForeArm", "LeftForeArm", "LeftHand", "LeftHand"],
	["LeftHand", "LeftHand", "", ""],
	["RightShoulder", "RightShoulder", "RightArm", "RightArm"],
	["RightArm", "RightArm", "RightForeArm", "RightForeArm"],
	["RightForeArm", "RightForeArm", "RightHand", "RightHand"],
	["RightHand", "RightHand", "", ""],
	["LeftUpLeg", "LeftUpLeg", "LeftLeg", "LeftLeg"],
	["LeftLeg", "LeftLeg", "LeftFoot", "LeftFoot"],
	["LeftFoot", "LeftFoot", "LeftToeBase", "LeftToeBase"],
	["LeftToeBase", "LeftToeBase", "", ""],
	["RightUpLeg", "RightUpLeg", "RightLeg", "RightLeg"],
	["RightLeg", "RightLeg", "RightFoot", "RightFoot"],
	["RightFoot", "RightFoot", "RightToeBase", "RightToeBase"],
	["RightToeBase", "RightToeBase", "", ""],
]
# Clip, FBX, remove the body's turn about the vertical (the game turns the body itself), extra turn (degrees) of the whole clip.
# The kick lands its foot 35 degrees across the body in the source; -35 aims it straight ahead.
const SOURCES := [
	["Turn_Left", "Turn Left 45 Degrees", true, 0.0],
	["Turn_Right", "Turning Right 45 Degrees", true, 0.0],
	["Kick", "Rifle Turn And Kick", false, 35.5],
	["Death_FromRight", "Death From Right", false, 0.0],
	["Death_Dying", "Dying", false, 0.0],
	["Death_HitToBack", "Rifle Hit To Back", false, 0.0],
]

var _hero: Skeleton3D
var _scale := 1.0
var _root_basis := Basis.IDENTITY
var _detrend := false # remove the hips' horizontal travel of a running clip (the game moves the hero)
var _frames: Array = [] # per-frame retargeted rotations of the last _bake, for the weapon fit


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var model := (load("res://models/objects/characters/soldier_animated.glb") as PackedScene).instantiate()
	root.add_child(model)
	_hero = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_root_basis = _hero.get_bone_global_rest(_hero.find_bone("Root")).basis.orthonormalized()
	var library := AnimationLibrary.new()
	for entry: Array in SOURCES:
		var animation := _bake(String(entry[1]), bool(entry[2]), deg_to_rad(float(entry[3])))
		if animation == null:
			quit(1)
			return
		library.add_animation(String(entry[0]), animation)
		var meta: Array[String] = []
		for key in animation.get_meta_list():
			meta.append("%s=%s" % [key, str(animation.get_meta(key)).left(40)])
		print("%-16s %5.2fs  %s" % [entry[0], animation.length, " ".join(meta)])
	_add_sprint_clips(library, model)
	var error := ResourceSaver.save(library, OUTPUT)
	print("saved ", OUTPUT, " -> ", error)
	quit(0 if error == OK else 1)


func _bake(file: String, remove_yaw: bool, extra_yaw: float) -> Animation:
	var packed := load(SOURCE_DIR + file + ".fbx") as PackedScene
	if packed == null:
		push_error("Missing " + file)
		return null
	var instance := packed.instantiate()
	root.add_child(instance)
	var source := instance.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var player := instance.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var clip := player.get_animation(player.get_animation_list()[0])
	_scale = _leg_length(_hero, "LeftUpLeg", "LeftFoot") / _leg_length(source, PREFIX + "LeftUpLeg", PREFIX + "LeftFoot")
	var count := int(round(clip.length * FPS)) + 1
	var frames: Array = []
	var yaws: Array[float] = []
	var reach := -INF
	var impact := 0.0
	var impact_foot := ""
	var hips := source.find_bone(PREFIX + "Hips")
	var start_heading := 0.0
	for index in count:
		_pose_source(source, clip, float(index) / FPS)
		var heading := _heading(source)
		if index == 0:
			start_heading = heading
		# The Mixamo characters do not all start facing the same way: the start heading is always removed.
		var yaw := (heading if remove_yaw else start_heading) + extra_yaw
		yaws.append(angle_difference(start_heading, heading))
		frames.append(_retarget(source, yaw))
		for foot in ["LeftFoot", "RightFoot"]:
			var offset := source.get_bone_global_pose(source.find_bone(PREFIX + foot)).origin - source.get_bone_global_pose(hips).origin
			var distance := Vector2(offset.x, offset.z).length()
			if distance > reach:
				reach = distance
				impact = float(index) / FPS
				impact_foot = foot
	instance.queue_free()
	_frames = frames
	var rest_hips := _hero.get_bone_rest(_hero.find_bone("Hips")).origin
	var first: Vector3 = frames[0]["HipsPosition"]
	var last: Vector3 = frames[count - 1]["HipsPosition"]
	for index in count:
		var frame: Dictionary = frames[index]
		var position: Vector3 = frame["HipsPosition"]
		if _detrend: # a loop returns to its first pose: whatever the hips have gone forward by is travel
			var drift := (last - first) * (float(index) / float(maxi(count - 1, 1)))
			position -= Vector3(drift.x, 0.0, drift.z)
		frame["HipsPosition"] = Vector3(rest_hips.x + position.x - first.x, rest_hips.y + position.y, rest_hips.z + position.z - first.z)
	var animation := Animation.new()
	animation.length = float(count - 1) / FPS
	animation.loop_mode = Animation.LOOP_NONE
	animation.step = 1.0 / FPS
	for entry: Array in MAP:
		var track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, NodePath(TRACK_ROOT + String(entry[0])))
		for index in count:
			animation.rotation_track_insert_key(track, float(index) / FPS, frames[index][entry[0]])
	var position_track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(position_track, NodePath(TRACK_ROOT + "Hips"))
	for index in count:
		animation.position_track_insert_key(position_track, float(index) / FPS, frames[index]["HipsPosition"])
	animation.set_meta("source", file)
	animation.set_meta("final_yaw", yaws[count - 1])
	if remove_yaw:
		animation.set_meta("turn_yaw", yaws[count - 1])
	var impact_index := int(round(impact * FPS))
	animation.set_meta("impact_time", impact)
	animation.set_meta("impact_foot", impact_foot)
	animation.set_meta("impact_yaw", yaws[impact_index])
	animation.optimize(0.002, 0.002)
	return animation


# Heading of the body about the vertical (radians, positive turns left), from the shoulder line.
func _heading(source: Skeleton3D) -> float:
	var across := source.get_bone_global_pose(source.find_bone(PREFIX + "LeftShoulder")).origin - source.get_bone_global_pose(source.find_bone(PREFIX + "RightShoulder")).origin
	return atan2(-across.z, across.x)


func _leg_length(skeleton: Skeleton3D, hip: String, ankle: String) -> float:
	return skeleton.get_bone_global_rest(skeleton.find_bone(hip)).origin.distance_to(skeleton.get_bone_global_rest(skeleton.find_bone(ankle)).origin)


func _pose_source(source: Skeleton3D, clip: Animation, time: float) -> void:
	source.reset_bone_poses()
	for track in clip.get_track_count():
		var bone := source.find_bone(String(clip.track_get_path(track).get_concatenated_subnames()))
		if bone < 0:
			continue
		match clip.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				source.set_bone_pose_rotation(bone, clip.rotation_track_interpolate(track, time))
			Animation.TYPE_POSITION_3D:
				source.set_bone_pose_position(bone, clip.position_track_interpolate(track, time))


func _delta(source: Skeleton3D, bone: int) -> Basis:
	var animated := source.get_bone_global_pose(bone).basis.orthonormalized()
	var rest := source.get_bone_global_rest(bone).basis.orthonormalized()
	return animated * rest.inverse()


# `yaw` turns the whole body back about the vertical (turn clips stay on the spot).
func _retarget(source: Skeleton3D, yaw: float) -> Dictionary:
	var result := {}
	var globals := {}
	var corrections := {}
	var unyaw := Basis(Vector3.UP, -yaw)
	for entry: Array in MAP:
		var bone: String = entry[0]
		var index := _hero.find_bone(bone)
		var source_index := source.find_bone(PREFIX + String(entry[1]))
		var rest := _hero.get_bone_global_rest(index)
		var delta := _delta(source, source_index)
		var wanted := delta * rest.basis.orthonormalized()
		var child_mixamo: String = entry[3]
		if not child_mixamo.is_empty():
			var child_index := source.find_bone(PREFIX + child_mixamo)
			var aim := (source.get_bone_global_pose(child_index).origin - source.get_bone_global_pose(source_index).origin).normalized()
			var current := (_hero.get_bone_global_rest(_hero.find_bone(entry[2])).origin - rest.origin).normalized()
			var turned := (delta * current).normalized()
			var fix := Basis.IDENTITY
			if turned.dot(aim) < 0.99999:
				fix = Basis(Quaternion(turned, aim))
			corrections[bone] = fix
			wanted = fix * wanted
		else:
			var parent_name := _hero.get_bone_name(_hero.get_bone_parent(index))
			wanted = (corrections.get(parent_name, Basis.IDENTITY) as Basis) * wanted
		wanted = unyaw * wanted
		var parent := _hero.get_bone_parent(index)
		var parent_basis := _root_basis
		if parent >= 0 and globals.has(_hero.get_bone_name(parent)):
			parent_basis = globals[_hero.get_bone_name(parent)]
		result[bone] = (parent_basis.inverse() * wanted).orthonormalized().get_rotation_quaternion()
		globals[bone] = wanted
	var hips := source.find_bone(PREFIX + "Hips")
	var move := source.get_bone_global_pose(hips).origin - source.get_bone_global_rest(hips).origin
	result["HipsPosition"] = unyaw * (move * _scale)
	return result


# ---- Sprint clips (Vadim, 25.11.2026): Mixamo runs with the arms, the gun put in the hand --------------------------------
# Standard Run is the one-handed sprint (pistol, uzi: the gun stays in the right hand, the left arm swings).
# Rifle Run is the two-handed sprint (rifle, shotgun, launcher, sniper rifle: held out to the side, a little raised).
# The clips are baked per gun (Sprint_<Gun>): they also carry the grip fingers, the sleeve shape and the gun's own tracks.
const SPRINT_ONE_HAND := {"Pistol": "Standard Run", "Uzi": "Standard Run"}
const SPRINT_TWO_HAND := {"Shotgun": "Rifle Run (1)", "Launcher": "Rifle Run (1)", "AK": "Rifle Run (1)", "M4": "Rifle Run (1)", "Sniper": "Rifle Run (1)"}
const SPRINT_REF_SPEED := 4.8
## Share of the idle hold's orientation the one-handed gun takes over from the swinging arm: 0 keeps it fixed in the hand (a turned gun looked detached, Vadim).
## Metres the long gun is lowered in the fit (skeleton space), so the left hand meets its foregrip: the launcher rode too high (Vadim).
const GUN_DROP := {"Launcher": 0.07}
const ONE_HAND_CARRY := 0.0
const GRIP_BONES_RIGHT := ["RightFingers1", "RightFingers2", "RightThumb1", "RightThumb2", "RightElbowSleeve"]
const GRIP_BONES_LEFT := ["LeftFingers1", "LeftFingers2", "LeftThumb1", "LeftThumb2"]


func _add_sprint_clips(library: AnimationLibrary, model: Node) -> void:
	var player := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var bases := {}
	_detrend = true
	for source: String in ["Standard Run", "Rifle Run (1)"]:
		var base := _bake(source, false, 0.0)
		if base == null:
			quit(1)
			return
		bases[source] = [base, _frames.duplicate()]
		_measure_sprint(base, _frames)
	for gun: String in SPRINT_ONE_HAND:
		_build_sprint(library, model, player, gun, SPRINT_ONE_HAND[gun], bases, false)
	for gun: String in SPRINT_TWO_HAND:
		_build_sprint(library, model, player, gun, SPRINT_TWO_HAND[gun], bases, true)


func _build_sprint(library: AnimationLibrary, model: Node, player: AnimationPlayer, gun: String, source: String, bases: Dictionary, two_hands: bool) -> void:
	var base: Animation = (bases[source][0] as Animation).duplicate(true)
	var frames: Array = bases[source][1]
	var idle := player.get_animation("Idle_" + gun)
	var weapon_path := "Character_Rig/Skeleton3D/RightHand/Weapon_" + gun
	var keep: Array = GRIP_BONES_RIGHT.duplicate()
	if two_hands:
		keep.append_array(GRIP_BONES_LEFT)
	# The idle hold's grip fingers, sleeve shape, drawn gun and hidden props.
	var weapon_pose_tracks: Array[int] = []
	for track in idle.get_track_count():
		var path := str(idle.track_get_path(track))
		var is_bone := path.begins_with(TRACK_ROOT)
		if is_bone and not (path.get_slice(":", 1) in keep):
			continue
		var copy := base.add_track(idle.track_get_type(track))
		base.track_set_path(copy, idle.track_get_path(track))
		base.track_insert_key(copy, 0.0, idle.track_get_key_value(track, 0))
		var kind := idle.track_get_type(track)
		if path == weapon_path and (kind == Animation.TYPE_POSITION_3D or kind == Animation.TYPE_ROTATION_3D):
			weapon_pose_tracks.append(copy)
	_fit_weapon(base, model, player, gun, frames, idle, weapon_pose_tracks, two_hands)
	base.loop_mode = Animation.LOOP_LINEAR
	library.add_animation("Sprint_" + gun, base)
	print("Sprint_%s %5.2fs tracks=%d ref_speed=%s" % [gun, base.length, base.get_track_count(), str(base.get_meta("ref_speed"))])


# Puts both of the gun's grips on both hands in every frame: the grip points keep the place they have on the hands in the
# gun's idle hold; the roll about the line between the hands follows the right hand.
func _fit_weapon(base: Animation, model: Node, player: AnimationPlayer, gun: String, frames: Array, idle: Animation, tracks: Array[int], two_hands: bool) -> void:
	var weapon := model.find_child("Weapon_" + gun, true, false) as Node3D
	var grip_r := (weapon.find_child(gun + "_Grip_R", true, false) as Node3D).position
	var grip_l := (weapon.find_child(gun + "_Grip_L", true, false) as Node3D).position
	var right := _hero.find_bone("RightHand")
	var left := _hero.find_bone("LeftHand")
	player.play("Idle_" + gun)
	player.seek(0.0, true)
	_hero.force_update_all_bone_transforms()
	var hand_r := _hero.get_bone_global_pose(right)
	var hand_l := _hero.get_bone_global_pose(left)
	var local := Transform3D.IDENTITY
	for track in idle.get_track_count():
		if str(idle.track_get_path(track)) != "Character_Rig/Skeleton3D/RightHand/Weapon_" + gun:
			continue
		match idle.track_get_type(track):
			Animation.TYPE_POSITION_3D: local.origin = idle.track_get_key_value(track, 0)
			Animation.TYPE_ROTATION_3D: local.basis = Basis(idle.track_get_key_value(track, 0) as Quaternion)
	var held := hand_r * local
	var offset_r := hand_r.affine_inverse() * (held * grip_r)
	var offset_l := hand_l.affine_inverse() * (held * grip_l)
	var palm := Vector3.RIGHT
	var up_w := held.basis.inverse() * (hand_r.basis * palm)
	var axis_w := (grip_l - grip_r).normalized()
	var frame_w := _frame(axis_w, up_w)
	player.stop()
	var position_track := -1
	var rotation_track := -1
	for track in tracks:
		if base.track_get_type(track) == Animation.TYPE_POSITION_3D:
			position_track = track
		else:
			rotation_track = track
	for cleared in [position_track, rotation_track]:
		while base.track_get_key_count(cleared) > 0:
			base.track_remove_key(cleared, 0)
	for index in frames.size():
		_hero.reset_bone_poses()
		for entry: Array in MAP:
			_hero.set_bone_pose_rotation(_hero.find_bone(entry[0]), frames[index][entry[0]])
		_hero.set_bone_pose_position(_hero.find_bone("Hips"), frames[index]["HipsPosition"])
		var pose_r := _hero.get_bone_global_pose(right)
		var pose_l := _hero.get_bone_global_pose(left)
		var target_r := pose_r * offset_r
		var target_l := pose_l * offset_l
		var turn := Basis.IDENTITY
		var origin := Vector3.ZERO
		if two_hands:
			turn = _frame((target_l - target_r).normalized(), pose_r.basis * palm) * frame_w.inverse()
			origin = (target_r + target_l) * 0.5 - turn * ((grip_r + grip_l) * 0.5) - Vector3(0.0, float(GUN_DROP.get(gun, 0.0)), 0.0)
		else:
			# One hand: the gun swings with the arm only half way, it stays pointed ahead, turning about the grip.
			turn = (pose_r.basis * local.basis).orthonormalized().slerp(held.basis.orthonormalized(), ONE_HAND_CARRY)
			origin = target_r - turn * grip_r
		var relative := pose_r.affine_inverse() * Transform3D(turn, origin)
		var time := float(index) / FPS
		base.position_track_insert_key(position_track, time, relative.origin)
		base.rotation_track_insert_key(rotation_track, time, relative.basis.orthonormalized().get_rotation_quaternion())
	_hero.reset_bone_poses()


# A rotation whose x axis is `axis` and whose xy plane leans toward `up`.
func _frame(axis: Vector3, up: Vector3) -> Basis:
	var z := axis.cross(up).normalized()
	return Basis(axis, z.cross(axis).normalized(), z)


# Pace and foot-landing phases of a sprint cycle, from the baked frames of the soldier skeleton.
func _measure_sprint(base: Animation, frames: Array) -> void:
	var count := frames.size()
	var speeds: Array[float] = []
	var lows := {}
	for foot in ["LeftFoot", "RightFoot"]:
		var bone := _hero.find_bone(foot)
		var previous := 0.0
		var lowest := INF
		var lowest_at := 0
		var series: Array[float] = []
		for index in count:
			_hero.reset_bone_poses()
			for entry: Array in MAP:
				_hero.set_bone_pose_rotation(_hero.find_bone(entry[0]), frames[index][entry[0]])
			_hero.set_bone_pose_position(_hero.find_bone("Hips"), frames[index]["HipsPosition"])
			var at := _hero.get_bone_global_pose(bone).origin - _hero.get_bone_global_pose(_hero.find_bone("Hips")).origin
			series.append(at.z)
			if at.y < lowest:
				lowest = at.y
				lowest_at = index
		for index in count - 1:
			var rate := (series[index + 1] - series[index]) * FPS
			if rate < -0.5:
				speeds.append(-rate)
		lows[foot] = float(lowest_at) / FPS / base.length
	speeds.sort()
	# The foot speed measured off the clip (about 2 m/s) would play it 2.4x fast at the sprint's 8.1 m/s: the cycle is paced for
	# a quick sprint instead (about 1.7x, a cycle of 0.4 s), the legs slide a little.
	print("measured planted-foot speed ", speeds[speeds.size() / 2] if not speeds.is_empty() else 0.0)
	base.set_meta("ref_speed", SPRINT_REF_SPEED)
	base.set_meta("contact_left", snappedf(lows["LeftFoot"], 0.01))
	base.set_meta("contact_right", snappedf(lows["RightFoot"], 0.01))
	print("sprint measure ", base.get_meta("source"), " ref=", base.get_meta("ref_speed"), " contacts L=", base.get_meta("contact_left"), " R=", base.get_meta("contact_right"))
