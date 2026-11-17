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
# Clip, FBX, remove the body's turn about the vertical (the game turns the body itself), end speed.
const SOURCES := [
	["Turn_Left", "Turn Left 45 Degrees", true],
	["Turn_Right", "Turning Right 45 Degrees", true],
	["Kick", "Rifle Turn And Kick", false],
	["Death_FromRight", "Death From Right", false],
	["Death_Dying", "Dying", false],
	["Death_HitToBack", "Rifle Hit To Back", false],
]

var _hero: Skeleton3D
var _scale := 1.0
var _root_basis := Basis.IDENTITY


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var model := (load("res://models/objects/characters/soldier_animated.glb") as PackedScene).instantiate()
	root.add_child(model)
	_hero = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_root_basis = _hero.get_bone_global_rest(_hero.find_bone("Root")).basis.orthonormalized()
	var library := AnimationLibrary.new()
	for entry: Array in SOURCES:
		var animation := _bake(String(entry[1]), bool(entry[2]))
		if animation == null:
			quit(1)
			return
		library.add_animation(String(entry[0]), animation)
		var meta: Array[String] = []
		for key in animation.get_meta_list():
			meta.append("%s=%s" % [key, str(animation.get_meta(key)).left(40)])
		print("%-16s %5.2fs  %s" % [entry[0], animation.length, " ".join(meta)])
	var error := ResourceSaver.save(library, OUTPUT)
	print("saved ", OUTPUT, " -> ", error)
	quit(0 if error == OK else 1)


func _bake(file: String, remove_yaw: bool) -> Animation:
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
		var yaw := heading if remove_yaw else start_heading
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
	var rest_hips := _hero.get_bone_rest(_hero.find_bone("Hips")).origin
	var first: Vector3 = frames[0]["HipsPosition"]
	for frame: Dictionary in frames:
		var position: Vector3 = frame["HipsPosition"]
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
