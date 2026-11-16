extends RefCounted
## One-time fixes to the baked soldier clips: the ground speed each cycle is paced for, and no root travel in the roll.

## Ground speed (m/s) of the planted foot in the cycle, measured on the model: a stealth walk and a run.
const WALK_SPEED := 0.5
const RUN_SPEED := 4.0


static func apply(player: AnimationPlayer, dodge_clip: StringName) -> void:
	for clip_name in player.get_animation_list():
		var animation := player.get_animation(clip_name)
		if clip_name.begins_with("Walk_"):
			animation.set_meta("ref_speed", WALK_SPEED)
		elif clip_name.begins_with("Run_"):
			animation.set_meta("ref_speed", RUN_SPEED)
	# The roll clip carries the body 4 m along its Root bone; the game moves the hero itself, so the clip stays in place.
	if not player.has_animation(dodge_clip):
		return
	var roll := player.get_animation(dodge_clip)
	for track in roll.get_track_count():
		if roll.track_get_type(track) == Animation.TYPE_POSITION_3D and str(roll.track_get_path(track)).ends_with(":Root"):
			for key in roll.track_get_key_count(track):
				roll.track_set_key_value(track, key, Vector3.ZERO)


## The roll clip scales every gun to nothing. Sets its Weapon_<name> scale tracks (and the magazine inside) so only
## `held_weapon` (e.g. &"AK") stays drawn through the roll; an empty name leaves the clip as it is.
static func hold_weapon(player: AnimationPlayer, dodge_clip: StringName, held_weapon: StringName) -> void:
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
