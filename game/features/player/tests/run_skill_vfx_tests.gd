extends SceneTree
## Skill presentation on the real player scene: buff loops start and stop
## with their buffs, passives attach the body overlay, Berserk lights the
## aura and the mask eyes, and one-shot effects clean themselves up, for
## the procedural effect set.

const PLAYER := preload("res://game/features/player/public/player.tscn")
const DASH_TRAIL := preload("res://game/features/player/dash_trail.gd")
const HIT_STOP := preload("res://game/features/player/skill_fx/hit_stop.gd")
const DASH_ZONE := preload("res://game/features/player/dash_floor_zone.gd")
const RANGE_DOME := preload("res://game/features/player/range_dome.gd")
const SKILL_EFFECTS := preload("res://game/features/player/mutation_skill_effects.gd")
const STRIKE := preload("res://game/features/player/skill_fx/strike_fx.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var player := PLAYER.instantiate() as CharacterBody3D
	stage.add_child(player)
	player.set_physics_process(false)
	await process_frame
	var effects: Node = player.get("mutation_effects")
	var vfx: Node = effects.get("vfx")
	_expect(vfx != null, "The skill effects own a presentation node.")
	vfx.call("configure_world", stage)

	effects.call("_start_buff", "storm_pulse", 0.3)
	_expect(vfx.call("has_loop", "storm_pulse"), "Storm Pulse shows its electric field.")
	effects.call("_start_buff", "bone_blades", 0.3)
	_expect(vfx.call("has_loop", "bone_blades"), "Bone Blades show their orbit.")
	_expect(vfx.call("has_range_dome", "storm_pulse") and vfx.call("has_range_dome", "bone_blades"), "Area buffs show their range dome.")
	await create_timer(0.9).timeout
	_expect(not vfx.call("has_loop", "storm_pulse") and not vfx.call("has_loop", "bone_blades"), "Buff loops end with their buffs.")
	_expect(not vfx.call("has_range_dome", "storm_pulse") and not vfx.call("has_range_dome", "bone_blades"), "Range domes end with their buffs.")

	var meshes := player.get_node("Body").find_children("*", "MeshInstance3D", true, false)
	vfx.call("set_passives", true, true)
	await create_timer(0.5).timeout
	_expect(float(vfx.call("overlay_value", "bone")) > 0.99 and float(vfx.call("overlay_value", "metal")) > 0.99, "Bone Armor and Hardened Tissue fade in.")
	_expect((meshes[0] as MeshInstance3D).material_overlay != null, "The body overlay is attached while a passive shows.")
	vfx.call("set_passives", false, false)
	await create_timer(0.5).timeout
	_expect((meshes[0] as MeshInstance3D).material_overlay == null, "No overlay pass is left when nothing shows.")

	effects.call("_start_buff", "berserk", 0.4)
	await create_timer(0.2).timeout
	_expect(vfx.call("aura_visible"), "Berserk wraps the body in its aura.")
	_expect(vfx.call("eyes_visible"), "Berserk lights red eyes in the mask.")
	await create_timer(0.8).timeout
	_expect(not vfx.call("aura_visible") and not vfx.call("eyes_visible"), "Aura and eyes fade when Berserk ends.")

	_expect(is_equal_approx(SKILL_EFFECTS.BLOOD_BURST_RADIUS, 2.4), "Blood Burst reaches 2.4 m (40% less than 4 m).")
	await _check_procedural(stage, player, effects, vfx)
	stage.queue_free()
	await process_frame
	print("Skill vfx tests: %d failure(s)." % failures)
	quit(failures)


# The sole procedural backend: hooks, geometry and bounded node lifetimes.
func _check_procedural(stage: Node3D, player: Node3D, effects: Node, vfx: Node) -> void:
	effects.call("_start_buff", "storm_pulse", 0.3)
	effects.call("_start_buff", "bone_blades", 0.3)
	_expect(vfx.call("has_loop", "storm_pulse") and vfx.call("has_loop", "bone_blades"), "Procedural buff loops start with their buffs.")
	await create_timer(0.9).timeout
	_expect(not vfx.call("has_loop", "storm_pulse") and not vfx.call("has_loop", "bone_blades"), "Procedural buff loops end with their buffs.")
	var before := stage.get_child_count()
	var player_before := player.get_child_count()
	vfx.call("spike_burst", Vector3.ZERO, 2.4)
	vfx.call("electric_pulse", Vector3.ZERO, 3.0)
	var chain: Array[Vector3] = [Vector3.ZERO, Vector3(3, 0, 0), Vector3(3, 0, 3)]
	vfx.call("chain_lightning", chain)
	var pool: Node3D = vfx.call("acid_pool", Vector3(2, 0, 0), 1.7, 0.3)
	_expect(pool != null, "Procedural acid pool exists.")
	vfx.call("spore_cocoon", Vector3(-2, 0, 0), 3.0, 0.2)
	# One node per cast plus range domes for the four area casts.
	_expect(stage.get_child_count() == before + 9, "Procedural casts appear in the world (%d)." % (stage.get_child_count() - before))
	vfx.set("_shield_ready", 0.0)
	vfx.call("energy_shield")
	vfx.call("heartbeat", 0.2)
	_expect(player.get_child_count() == player_before + 2, "Procedural shield and heart ride on the player.")
	var beats := player.find_children("Sfx_skill_heartbeat", "AudioStreamPlayer3D", true, false)
	_expect(beats.size() == 1, "Heart animation starts one heartbeat voice")
	var beat := beats[0] as AudioStreamPlayer3D if not beats.is_empty() else null
	if beat != null:
		_expect(beat.stream is AudioStreamOggVorbis and beat.stream.resource_path.ends_with("heartbeat/very_loud_a_strong_b_1.ogg"), "Heart animation uses the supplied Vorbis recording")
		_expect(not (beat.stream as AudioStreamOggVorbis).loop, "Heartbeat recording plays once per animation")
		var before_move := beat.global_position
		player.position.x += 1.0
		_expect(beat.global_position.is_equal_approx(before_move + Vector3.RIGHT), "Heartbeat travels with the heart and player")
		player.position.x -= 1.0
	paused = true
	await create_timer(0.3).timeout
	_expect(is_instance_valid(beat), "Paused heart retains its sound voice")
	paused = false
	await create_timer(0.35).timeout
	_expect(not is_instance_valid(beat), "Heartbeat voice ends with the short animation, before its two-second recording ends")
	var trail := DASH_TRAIL.start(stage, player, 0.15)
	_expect(trail != null, "Predator Dash leaves a procedural trail.")
	var zone := DASH_ZONE.spawn(stage, stage.get_world_3d(), Vector3.ZERO, Vector3.FORWARD, 0.15)
	_expect(zone != null and zone.mesh.get_surface_count() == 1, "Predator Dash marks its strike lane on the floor.")
	_expect(DASH_ZONE.spawn(stage, stage.get_world_3d(), Vector3.ZERO, Vector3.ZERO, 0.15) == null, "A dash with no heading marks nothing.")
	# The centre is at body height, the strike must still lie flat and point where the player faces.
	var strike := STRIKE.play(stage, Vector3(0.0, 0.9, 0.0), Vector3(1.0, 0.0, 0.0))
	_expect(strike != null and absf(strike.global_basis.z.y) < 0.001 and absf(strike.global_basis.z.x + 1.0) < 0.001, "Power Strike lies flat and points along its heading.")
	var warm := Node3D.new()
	stage.add_child(warm)
	vfx.call("warm_up", warm)
	_expect(warm.get_child_count() >= 4, "Dash and strike warm-up play in the hidden viewport.")
	warm.queue_free()
	HIT_STOP.pulse(self, 0.05)
	_expect(is_equal_approx(Engine.time_scale, HIT_STOP.SLOW_SCALE), "A heavy hit slows time for a moment.")
	await create_timer(0.2).timeout
	_expect(is_equal_approx(Engine.time_scale, 1.0), "The slow-down ends by itself.")
	for frame in 20:
		await process_frame
	await create_timer(1.6).timeout
	_expect(stage.get_child_count() == before, "Procedural casts free themselves.")
	_expect(player.get_child_count() == player_before, "Procedural shield and heart free themselves.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
