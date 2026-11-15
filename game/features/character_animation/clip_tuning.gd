extends RefCounted
## One-time fixes to the baked soldier clips: the ground speed each cycle is paced for, and no root travel in the roll.

## Ground speed (m/s) of the planted foot in the cycle, measured on the model: a stealth walk and a run.
const WALK_SPEED := 0.5
const RUN_SPEED := 3.7


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
