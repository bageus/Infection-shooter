extends SceneTree
## Retargets the Mixamo zombie FBX clips onto the Hunger skeleton (ADR-0045).
##
## Run after an editor import of models/objects/characters/enemy/hunger_clips/*.fbx:
##   godot --headless --path . --script res://tools/build_hunger_clips.gd
##
## Writes models/objects/characters/enemy/game/Hunger_mixamo.res, an
## AnimationLibrary with rotation tracks for the 21 skinned bones and a position
## track for the hips. Unlike the player's leg clips these are full-body.
##
## Method (per bone, parents first): the Mixamo world-space turn away from its
## rest pose is applied to the Hunger rest pose, then the bone is aimed along
## the Mixamo bone direction, so the A-pose rest of the Hunger and the T-pose of
## Mixamo do not matter. Leaf bones (head, hands, toes) take the correction of
## their parent. Hips travel is scaled by the leg-length ratio.
##
## Besides the 13 source clips the tool bakes what the set lacks (all of it is
## listed in ADR-0045): the left-hand attacks (mirrored), a walk, the stand to
## all-fours and stand to crawl transitions, the idle poses on all fours and on
## the belly, and the crawl attack.

const ENEMY_DIR := "res://models/objects/characters/enemy/game/"
const SOURCE_DIRS := [
	"res://models/objects/characters/enemy/hunger_clips/",
	"res://models/objects/characters/enemy/clips/",
]
const FPS := 30.0
const MIRROR := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
const PREFIX := "mixamorig_"
# Hunger bone, Mixamo bone, Hunger child that gives the direction, Mixamo child.
const MAP := [
	["Hips", "Hips", "Spine", "Spine"],
	["Spine", "Spine", "Chest", "Spine2"],
	["Chest", "Spine2", "Neck", "Neck"],
	["Neck", "Neck", "Head", "Head"],
	["Head", "Head", "", ""],
	["L_Shoulder", "LeftShoulder", "L_UpperArm", "LeftArm"],
	["L_UpperArm", "LeftArm", "L_Forearm", "LeftForeArm"],
	["L_Forearm", "LeftForeArm", "L_Hand", "LeftHand"],
	["L_Hand", "LeftHand", "", ""],
	["R_Shoulder", "RightShoulder", "R_UpperArm", "RightArm"],
	["R_UpperArm", "RightArm", "R_Forearm", "RightForeArm"],
	["R_Forearm", "RightForeArm", "R_Hand", "RightHand"],
	["R_Hand", "RightHand", "", ""],
	["L_Thigh", "LeftUpLeg", "L_Shin", "LeftLeg"],
	["L_Shin", "LeftLeg", "L_Foot", "LeftFoot"],
	["L_Foot", "LeftFoot", "L_Toe", "LeftToeBase"],
	["L_Toe", "LeftToeBase", "", ""],
	["R_Thigh", "RightUpLeg", "R_Shin", "RightLeg"],
	["R_Shin", "RightLeg", "R_Foot", "RightFoot"],
	["R_Foot", "RightFoot", "R_Toe", "RightToeBase"],
	["R_Toe", "RightToeBase", "", ""],
]
# Source clips: name, FBX, mirror, loop, root travel ("loop" mean | "first" frame), yaw removal, trim range (-1 = whole).
const SOURCES := [
	["Idle", "Zombie_Idle", false, true, false, -1.0, -1.0],
	["Agonize", "Zombie_Agonizing", false, false, false, -1.0, -1.0],
	["Scream", "Zombie_Scream", false, false, false, -1.0, -1.0],
	["TurnRight", "Zombie_Turn_1", false, false, true, -1.0, -1.0],
	["TurnLeft", "Zombie_Turn_1", true, false, true, -1.0, -1.0],
	["Run", "Zombie_Run", false, true, false, -1.0, -1.0],
	["RunLunge", "Mutant_Run", false, true, false, -1.0, -1.0],
	["FoursRun", "Running_Crawl", false, true, false, -1.0, -1.0],
	["Crawl", "Zombie_Crawl", false, true, false, -1.0, -1.0],
	["HitReaction", "Zombie_Reaction_Hit", false, false, false, -1.0, -1.0],
	["AttackRight", "Zombie_Attack_1", false, false, false, -1.0, -1.0],
	["AttackLeft", "Zombie_Attack_1", true, false, false, -1.0, -1.0],
	["AttackRight2", "Zombie_Punching", false, false, false, -1.0, -1.0],
	["AttackLeft2", "Zombie_Punching", true, false, false, -1.0, -1.0],
	["BiteLoop", "zombie_biting_2", false, true, false, -1.0, -1.0],
]
const BITE_SOURCE := "zombie_biting"
const ALL := ["Hunger", "Revenant", "Brute", "Colossus", "Titan"]
const HEAVY_ALL := ["Revenant", "Brute", "Colossus", "Titan"]
const BIG := ["Colossus", "Titan"]
const BRAWLERS := ["Brute", "Colossus", "Titan"]
# Clips added to every enemy listed in "enemies" (the owner's list of 16.11.2026). Keys: name,
# file, enemies, mirror, loop, yaw (turn clips: remove the hips yaw, kept as a curve), pace
# (walk / wander: stretched to the gameplay speed, run: measured; all set ref_speed and own_pace),
# inplace (the hips drift over the clip is removed, the clip ends where it began),
# series (numbered AttackLeft, AttackLeft2 ... in the order listed per enemy), cap (death clips:
# most metres the body may travel), settle (climb: the last frame is the standing pose).
const EXTRA := [
	{"name": "Transition", "file": "Zombie Transition", "enemies": ALL, "inplace": true},
	{"name": "IdleZombie1", "file": "Zombie Idle_1", "enemies": ALL, "loop": true},
	{"name": "IdleZombie2", "file": "Zombie Idle_2", "enemies": ALL, "loop": true},
	{"name": "IdleZombie3", "file": "Zombie Idle_3", "enemies": ALL, "loop": true},
	{"name": "IdleZombie4", "file": "Zombie Idle_4", "enemies": ALL, "loop": true},
	{"name": "IdleOrc", "file": "Orc Idle", "enemies": ALL, "loop": true},
	{"name": "IdleOldMan", "file": "Old Man Idle", "enemies": ALL, "loop": true},
	{"name": "IdleMutant", "file": "Mutant Idle", "enemies": BIG, "loop": true},
	{"name": "IdleScratch", "file": "Zombie Scratch Idle", "enemies": BIG, "loop": true},
	{"name": "DeathSide", "file": "Zombie Stumbling", "enemies": ALL, "cap": 1.1},
	{"name": "DeathSide2", "file": "Zombie Stumbling", "enemies": ALL, "mirror": true, "cap": 1.1},
	{"name": "DeathForward", "file": "Zombie Dying", "enemies": ALL, "cap": 1.1},
	{"name": "DeathBack", "file": "Stumble Backwards", "enemies": ALL, "cap": 1.1},
	{"name": "HitReaction", "file": "Zombie_Reaction_Hit", "enemies": HEAVY_ALL},
	{"name": "TurnLeft", "file": "Left Turn", "enemies": HEAVY_ALL, "yaw": true},
	{"name": "TurnRight", "file": "Left Turn_1", "enemies": HEAVY_ALL, "yaw": true},
	{"name": "TurnLeft2", "file": "Left Turn", "enemies": ["Hunger"], "yaw": true},
	{"name": "TurnRight2", "file": "Left Turn_1", "enemies": ["Hunger"], "yaw": true},
	{"name": "Walk", "file": "Mutant Walking", "enemies": BIG, "loop": true, "pace": "walk"},
	{"name": "WalkWander", "file": "Drunk Walk", "enemies": ["Revenant"], "loop": true, "pace": "wander"},
	{"name": "WalkWander", "file": "Old Man Walk", "enemies": BRAWLERS, "loop": true, "pace": "wander"},
	{"name": "RunZombie", "file": "Zombie_Run", "enemies": ["Brute"], "loop": true, "pace": "run"},
	{"name": "RunForward", "file": "Run Forward", "enemies": ["Revenant", "Brute", "Titan"], "loop": true, "pace": "run"},
	{"name": "Climb", "file": "Climbing", "enemies": ALL, "settle": true},
	{"series": "AttackLeft", "file": "Zombie Attack", "enemies": ["Revenant", "Brute", "Colossus", "Titan"]},
	{"series": "AttackLeft", "file": "Mutant Punch", "enemies": BRAWLERS},
	{"series": "AttackLeft", "file": "Mutant Swiping", "enemies": BRAWLERS},
	{"series": "AttackLeft", "file": "Stable Sword Inward Slash_2", "enemies": BRAWLERS},
	{"series": "AttackRight", "file": "Zombie Attack_2", "enemies": ["Revenant", "Brute", "Colossus", "Titan"]},
	{"series": "AttackRight", "file": "Mutant Punch_1", "enemies": BIG},
	{"series": "AttackRight", "file": "Mutant Swiping_1", "enemies": BIG},
	{"series": "AttackRight", "file": "Stable Sword Inward Slash", "enemies": BIG},
]
# Walks and runs are paced by stance-foot speed against the hips; wanderers move at this share of move_speed.
const WANDER_SHARE := 0.35
# Ground speed (m/s) each locomotion cycle is paced for; the driver scales playback by speed / ref_speed.
# Heavy humanoids (the rest of the roster) take only Idle/Walk/Run; their attacks, death and
# hit clips stay procedural. Per enemy: Mixamo source of the Run clip, Body scale (the clip's
# ground speed is measured in skeleton units), gameplay walk speed, how far the walk is pulled
# toward the idle pose (shorter stride) and the cap on the walk slow-down.
const HEAVY := {
	"Revenant": {"run": "Zombie_Run", "scale": 1.0, "walk_mps": 1.84, "run_mps": 4.6, "walk_amount": 0.6},
	"Brute": {"run": "Mutant_Run", "scale": 1.1, "walk_mps": 1.64, "run_mps": 4.1, "walk_amount": 0.55},
	"Titan": {"run": "Mutant_Run", "scale": 1.35, "walk_mps": 1.32, "run_mps": 3.3, "walk_amount": 0.5},
	"Colossus": {"run": "Mutant_Run", "scale": 1.55, "walk_mps": 1.16, "run_mps": 2.9, "walk_amount": 0.45},
}
const REF_SPEED := {"Walk": 2.16, "Run": 5.4, "RunLunge": 5.4, "FoursRun": 5.4, "Crawl": 1.2}
# Bones may dip this far below the floor before a clip is lifted.
const SINK_TOLERANCE := 0.01
const WALK_STRETCH := 2.1
const WALK_AMOUNT := 0.62

var _enemy_name := "Hunger"
var _hunger: Skeleton3D
var _scale := 1.0
var _root_basis := Basis.IDENTITY
var _floor := 0.0
var _frames := {} # clip name -> Array[Dictionary]
var _meta := {} # clip name -> Dictionary
var _loops := {} # clip name -> bool


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_enemy_name = args[0]
	var model := (load(ENEMY_DIR + _enemy_name + "_rig.tscn") as PackedScene).instantiate()
	root.add_child(model)
	_hunger = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_root_basis = _hunger.get_bone_global_rest(_hunger.find_bone("Root")).basis.orthonormalized()
	_floor = _hunger.get_bone_global_rest(_hunger.find_bone("Root")).origin.y
	if HEAVY.has(_enemy_name):
		_bake_heavy(HEAVY[_enemy_name])
	else:
		for entry: Array in SOURCES:
			if not _bake_source(entry):
				quit(1)
				return
		if not _bake_bite():
			quit(1)
			return
		_bake_synthetic()
	_bake_extra()
	var library := AnimationLibrary.new()
	for clip_name: String in _frames:
		var animation := _emit(clip_name)
		library.add_animation(clip_name, animation)
		print("%-14s %5.2fs  %3d frames  lowest %.3f m  %s" % [clip_name, animation.length, _frames[clip_name].size(), _lowest(_frames[clip_name]), _describe(animation)])
	var output := ENEMY_DIR + _enemy_name + "_mixamo.res"
	var error := ResourceSaver.save(library, output)
	print("saved ", output, " -> ", error)
	quit(0 if error == OK else 1)


# ---------------------------------------------------------------- heavy humanoids

func _bake_heavy(style: Dictionary) -> void:
	for entry: Array in SOURCES:
		if entry[0] == "Idle":
			_bake_source(entry)
	var run_name: String = style["run"]
	_bake_source(["Run", run_name, false, true, false, -1.0, -1.0])
	var idle: Dictionary = _frames["Idle"][0]
	var run_frames: Array = _frames["Run"]
	# Walk: the run pulled toward the idle pose (short stride), stretched so that the
	# stance foot moves at the gameplay walk speed when the clip plays at 1x.
	var amount: float = style["walk_amount"]
	var base: Array = []
	for frame: Dictionary in run_frames:
		base.append(_blend(idle, frame, amount))
	var stride := _ground_speed(base) * float(style["scale"]) # m/s at 1x
	var stretch := clampf(stride / float(style["walk_mps"]), 1.0, 4.0)
	var walk: Array = []
	var walk_count := int(round(base.size() * stretch))
	for index in walk_count:
		var position := float(index) / float(walk_count) * base.size()
		var low := int(floor(position)) % base.size()
		walk.append(_blend(base[low], base[(low + 1) % base.size()], position - floor(position)))
	_clamp_to_floor(walk)
	_frames["Walk"] = walk
	_loops["Walk"] = true
	_finish_meta("Walk", walk, true)
	_clamp_to_floor(_frames["Run"])
	_meta["Walk"]["ref_speed"] = _ground_speed(walk) * float(style["scale"])
	_meta["Run"]["ref_speed"] = _ground_speed(run_frames) * float(style["scale"])
	for key in ["Idle"]: # the procedural idle stays
		_frames.erase(key)
		_loops.erase(key)
		_meta.erase(key)
	print("%s: walk stretch %.2f ref %.2f (gameplay %.2f), run ref %.2f (gameplay %.2f)" % [_enemy_name, stretch, _meta["Walk"]["ref_speed"], style["walk_mps"], _meta["Run"]["ref_speed"], style["run_mps"]])


# ---------------------------------------------------------------- the owner's added clips

func _body_scale() -> float:
	return float(HEAVY[_enemy_name]["scale"]) if HEAVY.has(_enemy_name) else 1.0


func _bake_extra() -> void:
	var series := {}
	for entry: Dictionary in EXTRA:
		if not _enemy_name in entry["enemies"]:
			continue
		var clip_name: String = entry.get("name", "")
		if entry.has("series"):
			var count: int = series.get(entry["series"], 0)
			series[entry["series"]] = count + 1
			clip_name = String(entry["series"]) + ("" if count == 0 else str(count + 1))
		var loop: bool = entry.get("loop", false)
		if not _bake_source([clip_name, entry["file"], entry.get("mirror", false), loop, entry.get("yaw", false), -1.0, -1.0]):
			push_error("Could not bake " + clip_name)
			quit(1)
			return
		if entry.has("cap"):
			_cap_travel(clip_name, float(entry["cap"]))
		if entry.get("settle", false):
			_settle_end(clip_name)
		if entry.get("inplace", false):
			_remove_drift(clip_name)
		if entry.has("pace"):
			_pace(clip_name, String(entry["pace"]))
		if loop and entry.get("pace", "") != "":
			_clamp_to_floor(_frames[clip_name])


# Walk and wander cycles are stretched until the stance foot moves at the gameplay speed at 1x;
# every paced clip names its own ground speed (ref_speed) and the driver follows it (own_pace).
func _pace(clip_name: String, kind: String) -> void:
	var scale := _body_scale()
	var style: Dictionary = HEAVY.get(_enemy_name, {})
	var target := 0.0
	if kind == "walk":
		target = float(style.get("walk_mps", 0.0))
	elif kind == "wander":
		target = float(style.get("run_mps", 0.0)) * WANDER_SHARE
	var frames: Array = _frames[clip_name]
	if target > 0.0:
		var stretch := clampf(_ground_speed(frames) * scale / target, 1.0, 4.0)
		var count := int(round(frames.size() * stretch))
		var stretched: Array = []
		for index in count:
			var position := float(index) / float(count) * frames.size()
			var low := int(floor(position)) % frames.size()
			stretched.append(_blend(frames[low], frames[(low + 1) % frames.size()], position - floor(position)))
		frames = stretched
		_frames[clip_name] = frames
	_meta[clip_name]["ref_speed"] = _ground_speed(frames) * scale
	_meta[clip_name]["own_pace"] = true
	print("%s %s: ref %.2f m/s, target %.2f" % [_enemy_name, clip_name, _meta[clip_name]["ref_speed"], target])


# A death clip may carry the body at most `metres` from where it stood (the fall adds its own slide).
func _cap_travel(clip_name: String, metres: float) -> void:
	var rest := _hunger.get_bone_rest(_hunger.find_bone("Hips")).origin
	var farthest := 0.0
	for frame: Dictionary in _frames[clip_name]:
		var position: Vector3 = frame["HipsPosition"]
		farthest = maxf(farthest, Vector2(position.x - rest.x, position.z - rest.z).length())
	var factor := minf(1.0, metres / maxf(farthest * _body_scale(), 0.001))
	for frame: Dictionary in _frames[clip_name]:
		var position: Vector3 = frame["HipsPosition"]
		frame["HipsPosition"] = Vector3(rest.x + (position.x - rest.x) * factor, position.y, rest.z + (position.z - rest.z) * factor)
	print("%s %s: travel %.2f m -> %.2f m" % [_enemy_name, clip_name, farthest * _body_scale(), farthest * _body_scale() * factor])


# Moves the hips back along a straight line so the last frame is over the first (no pop into the idle after it).
func _remove_drift(clip_name: String) -> void:
	var frames: Array = _frames[clip_name]
	var span := float(frames.size() - 1)
	var drift: Vector3 = (frames[frames.size() - 1]["HipsPosition"] as Vector3) - (frames[0]["HipsPosition"] as Vector3)
	drift.y = 0.0
	for index in frames.size():
		frames[index]["HipsPosition"] = (frames[index]["HipsPosition"] as Vector3) - drift * (float(index) / span)


# The climb out of the hole ends standing where the enemy was spawned, so the whole clip is moved
# until its last frame is at the rest height and place; the start is then under the floor.
func _settle_end(clip_name: String) -> void:
	var frames: Array = _frames[clip_name]
	var rest := _hunger.get_bone_rest(_hunger.find_bone("Hips")).origin
	var end: Vector3 = frames[frames.size() - 1]["HipsPosition"]
	var shift := end - rest
	for frame: Dictionary in frames:
		frame["HipsPosition"] = (frame["HipsPosition"] as Vector3) - shift
	print("%s %s: starts %.2f m below, %.2f m behind" % [_enemy_name, clip_name, (rest.y - (frames[0]["HipsPosition"] as Vector3).y) * _body_scale(), (frames[0]["HipsPosition"] as Vector3).z * _body_scale()])


# Ground speed of a loop in skeleton units: how fast the planted foot moves back against the hips.
func _ground_speed(frames: Array) -> float:
	var total := 0.0
	var samples := 0
	var previous := {}
	for frame: Dictionary in frames:
		var points := _positions(frame, ["L_Foot", "R_Foot", "Hips"])
		var low := "L_Foot" if (points["L_Foot"] as Vector3).y < (points["R_Foot"] as Vector3).y else "R_Foot"
		var relative: Vector3 = (points[low] as Vector3) - (points["Hips"] as Vector3)
		if previous.has(low):
			var step: Vector3 = (previous[low] as Vector3) - relative
			total += Vector2(step.x, step.z).length() * FPS
			samples += 1
		previous = {low: relative}
	return total / maxf(samples, 1)


# ---------------------------------------------------------------- sources

func _bake_source(entry: Array) -> bool:
	var frames := _source_frames(String(entry[1]), bool(entry[2]), bool(entry[4]), float(entry[5]), float(entry[6]), bool(entry[3]))
	if frames.is_empty():
		return false
	var name: String = entry[0]
	if bool(entry[3]):
		frames = _close_loop(frames)
	_frames[name] = frames
	_loops[name] = bool(entry[3])
	_finish_meta(name, frames, bool(entry[3]))
	return true


# Splits zombie_biting.fbx into the way down, and the way up (the middle is the
# feeding loop, which zombie_biting_2 covers better).
func _bake_bite() -> bool:
	var frames := _source_frames(BITE_SOURCE, false, false, -1.0, -1.0, false)
	if frames.is_empty():
		return false
	var heights: Array[float] = []
	var lowest := INF
	for frame: Dictionary in frames:
		var height: float = (frame["HipsPosition"] as Vector3).y
		heights.append(height)
		lowest = minf(lowest, height)
	var rest_height := heights[0]
	var down_end := 0
	var up_start := frames.size() - 1
	for index in frames.size():
		if heights[index] <= lowest + 0.05:
			down_end = index
			break
	for index in range(frames.size() - 1, -1, -1):
		if heights[index] <= lowest + 0.05:
			up_start = index
			break
	print("bite split: down 0..%d (%.2fs), up %d..%d (%.2fs), hips %.2f -> %.2f" % [down_end, down_end / FPS, up_start, frames.size() - 1, (frames.size() - 1 - up_start) / FPS, rest_height, lowest])
	_frames["BiteDown"] = frames.slice(0, down_end + 1)
	_frames["BiteUp"] = frames.slice(up_start)
	_loops["BiteDown"] = false
	_loops["BiteUp"] = false
	_finish_meta("BiteDown", _frames["BiteDown"], false)
	_finish_meta("BiteUp", _frames["BiteUp"], false)
	return true


# Samples a source FBX into Hunger-skeleton frames: {bone: Quaternion, "HipsPosition": Vector3}.
func _source_frames(file: String, mirror: bool, remove_yaw: bool, from_time: float, to_time: float, loop: bool) -> Array:
	var packed: PackedScene = null
	for dir: String in SOURCE_DIRS:
		if ResourceLoader.exists(dir + file + ".fbx"):
			packed = load(dir + file + ".fbx") as PackedScene
			break
	if packed == null:
		push_error("Missing " + file)
		return []
	var instance := packed.instantiate()
	root.add_child(instance)
	var source := instance.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var player := instance.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var clip := player.get_animation(player.get_animation_list()[0])
	_scale = _leg_length(_hunger, "L_Thigh", "L_Foot") / _leg_length(source, PREFIX + "LeftUpLeg", PREFIX + "LeftFoot")
	var start := maxf(from_time, 0.0)
	var end := clip.length if to_time < 0.0 else minf(to_time, clip.length)
	var count := int(round((end - start) * FPS)) + 1
	var first_delta := Basis.IDENTITY
	var frames: Array = []
	var yaws: Array[float] = []
	for index in count:
		_pose_source(source, clip, start + float(index) / FPS)
		var hips_delta := _delta(source, source.find_bone(PREFIX + "Hips"))
		if mirror:
			hips_delta = MIRROR * hips_delta * MIRROR
		if index == 0:
			first_delta = hips_delta
		var yaw := 0.0
		if remove_yaw:
			var turned := (hips_delta * first_delta.inverse()) * Vector3.BACK
			yaw = atan2(turned.x, turned.z)
		yaws.append(yaw)
		frames.append(_retarget(source, mirror, yaw))
	instance.queue_free()
	# Root travel: the first frame stays the origin of one-shots, loops keep only the sway.
	var reference := Vector3.ZERO
	if loop:
		for frame: Dictionary in frames:
			reference += frame["HipsPosition"] as Vector3
		reference /= float(frames.size())
	else:
		reference = frames[0]["HipsPosition"] as Vector3
	var rest_hips := _hunger.get_bone_rest(_hunger.find_bone("Hips")).origin
	for frame: Dictionary in frames:
		var position: Vector3 = frame["HipsPosition"]
		frame["HipsPosition"] = Vector3(rest_hips.x + position.x - reference.x, rest_hips.y + position.y, rest_hips.z + position.z - reference.z)
	_lift_out_of_floor(frames)
	if remove_yaw:
		frames[0]["yaw_curve"] = yaws
	return frames


# Low poses (all fours, belly) put hands and chest below the floor because the
# Hunger arms are shorter than Mixamo's; the whole clip is lifted by the deepest dip.
func _lift_out_of_floor(frames: Array) -> void:
	var dip := _lowest(frames)
	if dip >= -SINK_TOLERANCE:
		return
	for frame: Dictionary in frames:
		var position: Vector3 = frame["HipsPosition"]
		position.y -= dip
		frame["HipsPosition"] = position


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


func _swapped(mixamo: String) -> String:
	if mixamo.begins_with("Left"):
		return "Right" + mixamo.substr(4)
	if mixamo.begins_with("Right"):
		return "Left" + mixamo.substr(5)
	return mixamo


# `yaw` turns the whole body back about the vertical (turn clips travel in place).
func _retarget(source: Skeleton3D, mirror: bool, yaw: float) -> Dictionary:
	var result := {}
	var globals := {} # Hunger bone -> new global basis
	var corrections := {}
	var unyaw := Basis(Vector3.UP, -yaw)
	for entry: Array in MAP:
		var bone: String = entry[0]
		var mixamo: String = PREFIX + (_swapped(entry[1]) if mirror else entry[1])
		var index := _hunger.find_bone(bone)
		var source_index := source.find_bone(mixamo)
		var rest := _hunger.get_bone_global_rest(index)
		var delta := _delta(source, source_index)
		if mirror:
			delta = MIRROR * delta * MIRROR
		var wanted := delta * rest.basis.orthonormalized()
		var child_mixamo: String = entry[3]
		if not child_mixamo.is_empty():
			var child_index := source.find_bone(PREFIX + (_swapped(child_mixamo) if mirror else child_mixamo))
			var aim := source.get_bone_global_pose(child_index).origin - source.get_bone_global_pose(source_index).origin
			if mirror:
				aim.x = -aim.x
			var current := (_hunger.get_bone_global_rest(_hunger.find_bone(entry[2])).origin - rest.origin).normalized()
			var turned := (delta * current).normalized()
			aim = aim.normalized()
			var fix := Basis.IDENTITY
			if turned.dot(aim) < 0.99999:
				fix = Basis(Quaternion(turned, aim))
			corrections[bone] = fix
			wanted = fix * wanted
		else:
			var parent_name := _hunger.get_bone_name(_hunger.get_bone_parent(index))
			wanted = (corrections.get(parent_name, Basis.IDENTITY) as Basis) * wanted
		wanted = unyaw * wanted
		var parent := _hunger.get_bone_parent(index)
		var parent_basis := _root_basis
		if parent >= 0 and globals.has(_hunger.get_bone_name(parent)):
			parent_basis = globals[_hunger.get_bone_name(parent)]
		result[bone] = (parent_basis.inverse() * wanted).orthonormalized().get_rotation_quaternion()
		globals[bone] = wanted
	var hips := source.find_bone(PREFIX + "Hips")
	var move := source.get_bone_global_pose(hips).origin - source.get_bone_global_rest(hips).origin
	if mirror:
		move.x = -move.x
	result["HipsPosition"] = unyaw * (move * _scale)
	return result


# ---------------------------------------------------------------- loops and blends

# Makes the last frame equal the first and drops it, so the cycle repeats without a seam.
func _close_loop(frames: Array) -> Array:
	var count := frames.size()
	var span := mini(6, count / 4)
	var result := frames.duplicate()
	for step in span:
		var index := count - span + step
		var weight := float(step + 1) / float(span)
		result[index] = _blend(frames[index], frames[0], weight)
	result.pop_back()
	if frames[0].has("yaw_curve"):
		result[0]["yaw_curve"] = frames[0]["yaw_curve"]
	return result


func _blend(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	var result := {}
	for key: String in a:
		if key == "HipsPosition":
			result[key] = (a[key] as Vector3).lerp(b[key] as Vector3, weight)
		elif key != "yaw_curve":
			result[key] = (a[key] as Quaternion).slerp(b[key] as Quaternion, weight)
	return result


func _smooth(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)


# `count` frames easing from pose a to pose b (both included).
func _transition(a: Dictionary, b: Dictionary, seconds: float, dip: float = 0.0) -> Array:
	var count := int(round(seconds * FPS)) + 1
	var frames: Array = []
	for index in count:
		var weight := _smooth(float(index) / float(count - 1))
		var frame := _blend(a, b, weight)
		var position: Vector3 = frame["HipsPosition"]
		position.y -= dip * sin(PI * weight)
		frame["HipsPosition"] = position
		frames.append(frame)
	return frames


# ---------------------------------------------------------------- synthetic clips

func _bake_synthetic() -> void:
	var idle: Dictionary = _frames["Idle"][0]
	var fours: Dictionary = _frames["FoursRun"][0]
	var crawl: Dictionary = _frames["Crawl"][0]
	# Walk: the run, slowed down and pulled toward the idle pose so the stride shortens.
	var run_frames: Array = _frames["Run"]
	var walk: Array = []
	var walk_count := int(round(run_frames.size() * WALK_STRETCH))
	for index in walk_count:
		var position := float(index) / float(walk_count) * run_frames.size()
		var low := int(floor(position)) % run_frames.size()
		var high := (low + 1) % run_frames.size()
		var sample := _blend(run_frames[low], run_frames[high], position - floor(position))
		walk.append(_blend(idle, sample, WALK_AMOUNT))
	_clamp_to_floor(walk)
	_frames["Walk"] = walk
	_loops["Walk"] = true
	_finish_meta("Walk", walk, true)
	# Stand <-> all fours, stand <-> belly crawl, all fours -> crawl.
	_add("DropToFours", _transition(idle, fours, 0.45, 0.04), false)
	_add("RiseFromFours", _transition(fours, idle, 0.55, 0.0), false)
	_add("CollapseToCrawl", _transition(idle, crawl, 0.75, -0.06), false)
	_add("FoursToCrawl", _transition(fours, crawl, 0.45, 0.0), false)
	# Poses held while standing still on all fours / on the belly, with a slow breath.
	_add("FoursIdle", _breathing(fours, 1.6), true)
	_add("CrawlIdle", _breathing(crawl, 1.8), true)
	# A crawling zombie claws at its prey: one crawl cycle at double speed.
	var cycle: Array = _frames["Crawl"]
	var claw: Array = []
	var claw_count := int(round(cycle.size() / 2.4))
	for index in claw_count:
		claw.append(cycle[int(float(index) / float(claw_count) * cycle.size()) % cycle.size()])
	claw.append(crawl)
	_add("CrawlAttack", claw, false)


func _add(clip_name: String, frames: Array, loop: bool) -> void:
	_clamp_to_floor(frames)
	_frames[clip_name] = frames
	_loops[clip_name] = loop
	_finish_meta(clip_name, frames, loop)


# A held pose with the chest and head swaying a few degrees.
func _breathing(pose: Dictionary, seconds: float) -> Array:
	var count := int(round(seconds * FPS))
	var frames: Array = []
	for index in count:
		var phase := float(index) / float(count) * TAU
		var frame := pose.duplicate()
		frame.erase("yaw_curve")
		for bone in ["Chest", "Neck", "Head"]:
			var sway := Quaternion(Vector3.RIGHT, deg_to_rad(1.6 if bone == "Chest" else 2.4) * sin(phase))
			frame[bone] = (pose[bone] as Quaternion) * sway
		var position: Vector3 = pose["HipsPosition"]
		position.y += 0.006 * sin(phase)
		frame["HipsPosition"] = position
		frames.append(frame)
	return frames


# Per frame: nothing may sink below the floor, so a blend between two poses that
# are both on the ground does not dip through it halfway.
func _clamp_to_floor(frames: Array) -> void:
	for frame: Dictionary in frames:
		var dip := _lowest([frame])
		if dip < -SINK_TOLERANCE:
			var position: Vector3 = frame["HipsPosition"]
			position.y -= dip
			frame["HipsPosition"] = position


# ---------------------------------------------------------------- output

func _emit(clip_name: String) -> Animation:
	var frames: Array = _frames[clip_name]
	var loop: bool = _loops[clip_name]
	var animation := Animation.new()
	animation.length = float(frames.size()) / FPS if loop else float(frames.size() - 1) / FPS
	animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	animation.step = 1.0 / FPS
	for entry: Array in MAP:
		var bone: String = entry[0]
		var track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, NodePath("Skeleton3D:" + bone))
		for index in frames.size():
			animation.rotation_track_insert_key(track, float(index) / FPS, frames[index][bone])
	var position_track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(position_track, NodePath("Skeleton3D:Hips"))
	for index in frames.size():
		animation.position_track_insert_key(position_track, float(index) / FPS, frames[index]["HipsPosition"])
	for key: String in _meta.get(clip_name, {}):
		animation.set_meta(key, _meta[clip_name][key])
	animation.optimize(0.002, 0.002)
	return animation


func _describe(animation: Animation) -> String:
	var parts: Array[String] = []
	for key in animation.get_meta_list():
		var value = animation.get_meta(key)
		parts.append("%s=%s" % [key, ("%.2f" % value) if value is float else str(value).left(40)])
	return " ".join(parts)


# ---------------------------------------------------------------- measurements

func _finish_meta(clip_name: String, frames: Array, loop: bool) -> void:
	var meta := {}
	if frames[0].has("yaw_curve"):
		var curve := PackedFloat32Array(frames[0]["yaw_curve"])
		meta["yaw_curve"] = curve
		meta["turn_yaw"] = curve[curve.size() - 1]
	if REF_SPEED.has(clip_name):
		meta["ref_speed"] = REF_SPEED[clip_name]
	if clip_name.begins_with("Attack"):
		meta["strike_time"] = _strike_time(frames, "R_Hand" if not clip_name.begins_with("AttackLeft") else "L_Hand")
	_meta[clip_name] = meta


# World positions (skeleton space) of the named bones for a frame.
func _positions(frame: Dictionary, names: Array) -> Dictionary:
	_hunger.reset_bone_poses()
	for entry: Array in MAP:
		_hunger.set_bone_pose_rotation(_hunger.find_bone(entry[0]), frame[entry[0]])
	_hunger.set_bone_pose_position(_hunger.find_bone("Hips"), frame["HipsPosition"])
	var result := {}
	for bone_name: String in names:
		result[bone_name] = _hunger.get_bone_global_pose(_hunger.find_bone(bone_name)).origin
	return result


func _lowest(frames: Array) -> float:
	var lowest := INF
	var names: Array = []
	for entry: Array in MAP:
		names.append(entry[0])
	for frame: Dictionary in frames:
		var points := _positions(frame, names)
		for bone_name: String in points:
			lowest = minf(lowest, (points[bone_name] as Vector3).y - _floor)
	return lowest


# When the striking hand is at its farthest in front of the chest (first strike of the clip).
func _strike_time(frames: Array, hand: String) -> float:
	var reach: Array[float] = []
	var best := 0.0
	for frame: Dictionary in frames:
		var points := _positions(frame, [hand, "Chest"])
		var distance := Vector2((points[hand] as Vector3).x - (points["Chest"] as Vector3).x, (points[hand] as Vector3).z - (points["Chest"] as Vector3).z).length()
		reach.append(distance)
		best = maxf(best, distance)
	for index in reach.size():
		if reach[index] >= best * 0.93:
			return float(index) / FPS
	return 0.0
