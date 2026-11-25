extends RefCounted
## One-time fixes to the baked soldier clips: the ground speed each cycle is paced for, and no root travel in the roll.

const OVERLAY := preload("res://game/features/character_animation/clip_overlay.gd")
const ARM_BONES := ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "LeftFingers1", "LeftFingers2", "LeftThumb1", "LeftThumb2",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand", "RightElbowSleeve", "RightFingers1", "RightFingers2", "RightThumb1", "RightThumb2"]

## Ground speed (m/s) of the planted foot in the cycle, measured on the model: a stealth walk and a run.
const WALK_SPEED := 0.5
## Measured planted-foot speed of each run cycle by direction (they differ, backward and sideways steps are shorter).
const RUN_SPEEDS := {"Forward": 3.75, "Forward_Left": 3.73, "Forward_Right": 3.73, "Left": 3.34, "Right": 3.52,
	"Backward": 3.42, "Backward_Left": 3.3, "Backward_Right": 3.2}
const RUN_SPEED_DEFAULT := 3.6
## The run cycle plays at this share of the speed-matched rate (Vadim: the legs were too fast); the stride is paced for slower steps.
const RUN_PACE := 0.8
## Seconds the roll's arm hold outlasts the roll: the cross-fade back to locomotion (enemy_blends.gd AFTER_ONE_SHOT).
const ROLL_ARMS_TAIL := 0.3


## "Run_Backward_Left_AK" -> the speed of the "Backward_Left" cycle.
static func _run_speed(clip_name: String) -> float:
	var tokens := clip_name.split("_")
	var key := tokens[1] + ("_" + tokens[2] if tokens.size() > 2 and tokens[2] in ["Left", "Right"] else "") if tokens.size() > 1 else ""
	return float(RUN_SPEEDS.get(key, RUN_SPEED_DEFAULT)) / RUN_PACE


static func apply(player: AnimationPlayer, dodge_clip: StringName) -> void:
	for clip_name in player.get_animation_list():
		var animation := player.get_animation(clip_name)
		if clip_name.begins_with("Walk_"):
			animation.set_meta("ref_speed", WALK_SPEED)
		elif clip_name.begins_with("Run_"):
			animation.set_meta("ref_speed", _run_speed(String(clip_name)))
	# The roll clip carries the body 4 m along its Root bone; the game moves the hero itself, so the clip stays in place.
	if not player.has_animation(dodge_clip):
		return
	var roll := player.get_animation(dodge_clip)
	for track in roll.get_track_count():
		if roll.track_get_type(track) == Animation.TYPE_POSITION_3D and str(roll.track_get_path(track)).ends_with(":Root"):
			for key in roll.track_get_key_count(track):
				roll.track_set_key_value(track, key, Vector3.ZERO)


## The roll clip scales every gun to nothing. Sets its Weapon_<name> scale tracks (and the magazine inside) so only
## `held_weapon` (e.g. &"AK") stays drawn through the roll; an empty name leaves the clip as it is. For `seconds` the arms
## also keep that gun's Idle hold (both hands on the grip), the roll clip's own arms point nowhere near each gun.
static func hold_weapon(player: AnimationPlayer, dodge_clip: StringName, held_weapon: StringName, seconds := 0.0, hold_prefix := &"Idle_") -> void:
	if held_weapon.is_empty() or player == null or not player.has_animation(dodge_clip):
		return
	var roll := player.get_animation(dodge_clip)
	for track in roll.get_track_count():
		var path := str(roll.track_get_path(track))
		var gun := path.get_slice("RightHand/Weapon_", 1).get_slice("/", 0).get_slice(":", 0) if "RightHand/Weapon_" in path else ""
		if gun.is_empty() or roll.track_get_type(track) != Animation.TYPE_SCALE_3D:
			continue
		for key in roll.track_get_key_count(track):
			roll.track_set_key_value(track, key, Vector3.ONE if gun == String(held_weapon) else Vector3.ZERO)
	var idle := StringName(String(hold_prefix) + String(held_weapon)) # the Idle hold, or the Sprint_ arms when the roll interrupts a sprint
	var skeletons := player.get_parent().find_children("*", "Skeleton3D", true, false)
	if seconds <= 0.0 or skeletons.is_empty() or not player.has_animation(idle):
		return
	var hold := skeletons[0].get_node_or_null("RollArms") as SkeletonModifier3D
	if hold == null:
		hold = OVERLAY.new()
		hold.name = "RollArms"
		hold.set("bones", ARM_BONES)
		hold.set("fade_in", 0.05)
		hold.set("fade_out", 0.12)
		skeletons[0].add_child(hold)
	# The base clip then cross-fades from the roll's own arms (a two-handed stance) into the locomotion clip for the next
	# AFTER_ONE_SHOT seconds: the hold lasts through that blend, or the arms show the roll's pose for a moment and snap.
	hold.call("play", player.get_animation(idle), seconds + ROLL_ARMS_TAIL)


## Playback rate of the legs kept on a locomotion cycle under a one-shot: the rate the player's main clip would run at
## (baked cycles name their paced speed), so a reload on the run keeps the stride; the driver's own scale otherwise.
static func leg_rate(driver: Node, clip: String, state: StringName, speed: float) -> float:
	var legs: bool = driver.get("_transition_legs") != ""
	var ref_speed := float(driver.animation_player.get_animation(clip).get_meta("ref_speed", 0.0)) if driver.clip_footsteps and legs and driver.animation_player.has_animation(clip) else 0.0
	if ref_speed <= 0.0:
		return driver._locomotion_scale(state if not legs else &"run", speed)
	return clampf(speed / ref_speed, 0.5, 2.4) * driver.locomotion_speed_multiplier * driver.leg_playback_multiplier


## The legs kept under the hero's reload follow what he does now (walk, run, turn), not what he did when it began.
static func follow_selector(driver: Node) -> String:
	var legs: String = driver.get("_transition_legs")
	var selector: Callable = driver.get("_clip_selector")
	if legs.is_empty() or not selector.is_valid() or driver.get("_dead"):
		return legs
	var now := String(selector.call())
	return now if driver.animation_player.has_animation(now) else legs
