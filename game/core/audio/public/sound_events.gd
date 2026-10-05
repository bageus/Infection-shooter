extends RefCounted
## Sound effect events (ADR-0018).
##
## Each event has several processed recordings in assets/audio/sfx/<event>/
## (see tools/build_sounds.py and assets/audio/CREDITS.md). Playback picks a
## variant, jitters pitch and level slightly so repeats sound natural, and
## places a self-freeing AudioStreamPlayer3D under `parent` (which must outlive
## the sound; pass an effects container for one-shots of freed emitters).
## Voices are capped per event and in total through scene groups, so there is
## no global state.

const ROOT := "res://assets/audio/sfx/"
const BUS := &"SFX"
const VOICE_GROUP := &"sfx_voice"
const MAX_VOICES := 48
const VARIANTS := 0
const VOLUME := 1
const DISTANCE := 2
const UNIT := 3
const JITTER := 4
const MAX_SAME := 5

# event: [variants, volume dB, max distance m, unit size m, pitch jitter, max simultaneous]
const EVENTS := {
	&"pistol_fire": [3, 0.0, 70.0, 9.0, 0.03, 4],
	&"uzi_fire": [4, -1.0, 70.0, 9.0, 0.04, 5],
	&"shotgun_fire": [3, 1.0, 80.0, 10.0, 0.03, 3],
	&"rifle_fire": [3, 1.0, 90.0, 10.0, 0.03, 3],
	&"assault_rifle_fire": [3, 0.0, 85.0, 10.0, 0.04, 5],
	&"launcher_fire": [2, 0.0, 70.0, 8.0, 0.03, 2],
	&"dry_fire": [2, -6.0, 15.0, 2.5, 0.05, 2],
	&"grenade_explode": [2, 3.0, 120.0, 14.0, 0.05, 3],
	&"extinguisher_burst": [2, 1.0, 80.0, 10.0, 0.05, 2],
	&"extinguisher_spray": [2, -2.0, 40.0, 4.0, 0.03, 2],
	&"canister_drop": [3, -1.0, 36.0, 3.5, 0.06, 2],
	&"pistol_reload": [3, -2.0, 20.0, 3.0, 0.02, 1],
	&"uzi_reload": [2, -2.0, 20.0, 3.0, 0.02, 1],
	&"shotgun_shell_load": [4, -2.0, 20.0, 3.0, 0.03, 2],
	&"launcher_reload": [2, -2.0, 20.0, 3.0, 0.02, 1],
	&"rifle_reload": [2, -2.0, 20.0, 3.0, 0.02, 1],
	&"casing_brass": [8, -6.0, 14.0, 1.6, 0.08, 6],
	&"casing_shell": [4, -5.0, 14.0, 1.8, 0.06, 4],
	&"casing_heavy": [3, -4.0, 16.0, 2.0, 0.06, 4],
	&"weapon_pickup": [2, -1.0, 20.0, 3.0, 0.02, 2],
	&"ammo_pickup": [2, -2.0, 20.0, 3.0, 0.04, 2],
	&"medkit_pickup": [1, -1.0, 20.0, 3.0, 0.04, 2],
	&"medkit_use": [1, -1.0, 20.0, 3.0, 0.03, 1],
	&"antidote_pickup": [1, -2.0, 20.0, 3.0, 0.05, 2],
	&"antidote_use": [1, -1.0, 20.0, 3.0, 0.03, 1],
	&"key_pickup": [2, 0.0, 20.0, 3.0, 0.03, 1],
	&"dna_pickup": [2, -1.0, 20.0, 3.0, 0.04, 2],
	&"step_player": [10, -4.0, 18.0, 2.2, 0.06, 2],
	&"step_light": [6, -5.0, 22.0, 2.4, 0.08, 6],
	&"step_heavy": [4, -1.0, 34.0, 4.0, 0.06, 4],
	&"step_horde": [4, -3.0, 26.0, 3.0, 0.1, 4],
	&"hit_metal": [4, -3.0, 40.0, 4.0, 0.06, 4],
	&"hit_wood": [5, -3.0, 36.0, 3.5, 0.07, 4],
	&"hit_paper": [3, -6.0, 24.0, 2.5, 0.08, 4],
	&"hit_electronics": [3, -3.0, 32.0, 3.5, 0.06, 4],
	&"hit_wall": [5, -4.0, 36.0, 3.5, 0.08, 4],
	&"hit_glass": [4, -3.0, 36.0, 3.5, 0.06, 4],
	&"glass_break": [4, 1.0, 60.0, 7.0, 0.05, 3],
	&"flesh_hit": [6, -2.0, 34.0, 4.0, 0.08, 5],
	&"dismember": [2, 1.0, 50.0, 6.0, 0.06, 3],
	&"body_part_fall": [2, -3.0, 24.0, 3.0, 0.08, 4],
	&"growl_zombie": [5, -2.0, 34.0, 4.0, 0.06, 3],
	&"growl_hunger": [3, -1.0, 36.0, 4.0, 0.05, 3],
	&"growl_revenant": [3, -2.0, 34.0, 4.0, 0.05, 3],
	&"growl_brute": [3, 0.0, 42.0, 5.0, 0.04, 2],
	&"growl_titan": [3, 1.0, 50.0, 6.0, 0.04, 2],
	&"growl_colossus": [3, 2.0, 60.0, 8.0, 0.03, 2],
	&"growl_horde": [2, 2.0, 55.0, 7.0, 0.04, 2],
	&"attack_swing": [4, -3.0, 24.0, 3.0, 0.08, 4],
	&"attack_hit": [4, 0.0, 30.0, 4.0, 0.06, 4],
	&"attack_bite": [3, 0.0, 30.0, 4.0, 0.06, 3],
	&"enemy_death": [4, -1.0, 40.0, 5.0, 0.05, 4],
	&"colossus_slam": [2, 4.0, 90.0, 12.0, 0.03, 2],
	&"horde_ram_hit": [2, 2.0, 60.0, 8.0, 0.04, 2],
	&"horde_summon": [2, 2.0, 70.0, 9.0, 0.03, 1],
	&"door_open": [2, -3.0, 26.0, 3.5, 0.05, 2],
	&"door_close": [2, -3.0, 26.0, 3.5, 0.05, 2],
	&"metal_door_open": [1, -2.0, 30.0, 4.0, 0.04, 2],
	&"metal_door_close": [1, -2.0, 30.0, 4.0, 0.04, 2],
	&"glass_door_open": [2, -3.0, 26.0, 3.5, 0.05, 2],
	&"glass_door_close": [1, -3.0, 26.0, 3.5, 0.05, 2],
	&"elevator_open": [1, -2.0, 32.0, 4.0, 0.0, 1],
	&"elevator_close": [1, -2.0, 32.0, 4.0, 0.0, 1],
	&"fall_wood": [4, -3.0, 32.0, 3.5, 0.08, 4],
	&"fall_metal": [2, -3.0, 36.0, 3.5, 0.08, 3],
	&"fall_light": [4, -5.0, 22.0, 2.5, 0.1, 4],
	&"fall_tech": [1, -4.0, 26.0, 3.0, 0.08, 3],
	&"fall_debris": [3, -6.0, 26.0, 3.0, 0.1, 4],
}


static func has_event(event: StringName) -> bool:
	return EVENTS.has(event)


# Plays `event` under `parent`; at `position` when given, else on the parent.
static var _voices := 0
static var _per_event: Dictionary = {}


static func play(parent: Node, event: StringName, position := Vector3.INF, volume_offset_db := 0.0, pitch := 1.0) -> AudioStreamPlayer3D:
	if parent == null or not parent.is_inside_tree() or not EVENTS.has(event):
		return null
	var spec: Array = EVENTS[event]
	var tree := parent.get_tree()
	var group := StringName("sfx_" + String(event))
	# Running counts instead of scanning groups for every footstep and clink.
	if int(_per_event.get(event, 0)) >= int(spec[MAX_SAME]) or _voices >= MAX_VOICES:
		return null
	var path := ROOT + "%s/%s_%d.ogg" % [event, event, randi_range(1, int(spec[VARIANTS]))]
	var stream := load(path) as AudioStream
	if stream == null:
		return null
	var player := AudioStreamPlayer3D.new()
	player.name = "Sfx_" + String(event)
	player.stream = stream
	player.bus = BUS if AudioServer.get_bus_index(BUS) >= 0 else &"Master"
	player.volume_db = float(spec[VOLUME]) + volume_offset_db + randf_range(-1.0, 1.0)
	var jitter := float(spec[JITTER])
	player.pitch_scale = maxf(0.1, pitch * (1.0 + randf_range(-jitter, jitter)))
	player.unit_size = float(spec[UNIT])
	player.max_distance = float(spec[DISTANCE])
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.attenuation_filter_cutoff_hz = 6500.0
	player.attenuation_filter_db = -12.0
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	player.add_to_group(VOICE_GROUP)
	player.add_to_group(group)
	_voices += 1
	_per_event[event] = int(_per_event.get(event, 0)) + 1
	player.tree_exiting.connect(func() -> void:
		_voices -= 1
		_per_event[event] = int(_per_event.get(event, 1)) - 1, CONNECT_ONE_SHOT)
	player.finished.connect(player.queue_free)
	parent.add_child(player)
	if position.is_finite():
		player.global_position = position
	if DisplayServer.get_name() == "headless":
		# No audio device: keep the voice for its duration without decoding,
		# so limits and tests behave the same and nothing plays at exit.
		var voice: WeakRef = weakref(player)
		tree.create_timer(stream.get_length() / player.pitch_scale).timeout.connect(func() -> void:
			var live := voice.get_ref() as Node
			if live != null:
				live.queue_free())
		return player
	player.play()
	return player
