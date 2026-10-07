extends SceneTree
## Skill presentation on the real player scene: buff loops start and stop
## with their buffs, passives attach the body overlay, Berserk lights the
## aura and the mask eyes, and one-shot effects clean themselves up, for
## both the sprite-sheet and the procedural effect sets.

const PLAYER := preload("res://game/features/player/public/player.tscn")
const DASH_TRAIL := preload("res://game/features/player/dash_trail.gd")
const RANGE_DOME := preload("res://game/features/player/range_dome.gd")
const SKILL_EFFECTS := preload("res://game/features/player/mutation_skill_effects.gd")

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
	var before := stage.get_child_count()
	vfx.call("spike_burst", Vector3.ZERO, 2.4)
	vfx.call("electric_pulse", Vector3.ZERO, 3.0)
	var chain: Array[Vector3] = [Vector3.ZERO, Vector3(3, 0, 0), Vector3(3, 0, 3)]
	vfx.call("chain_lightning", chain)
	vfx.call("acid_pool", Vector3(2, 0, 0), 2.2, 0.3)
	vfx.call("spore_cocoon", Vector3(-2, 0, 0), 3.0, 0.2)
	# 5 sheets (two chain links; the cocoon sheet starts later, so its burst
	# still lands on the fuse) plus range domes for the four area casts.
	_expect(stage.get_child_count() == before + 9, "Cast effects appear in the world (%d)." % (stage.get_child_count() - before))
	var domes: Array[Node] = stage.get_children().filter(func(node: Node) -> bool: return node.get_script() == RANGE_DOME)
	_expect(domes.size() == 4, "Each area cast shows its range dome (%d)." % domes.size())
	var burst_dome: MeshInstance3D = null
	for dome in domes:
		if (dome as Node3D).global_position.distance_to(Vector3.ZERO) < 0.1 and is_equal_approx((dome as Node3D).scale.x, 2.4):
			burst_dome = dome
	_expect(burst_dome != null, "The Blood Burst dome covers its 2.4 m radius.")
	if burst_dome != null:
		var top := burst_dome.get_aabb().end.y * burst_dome.scale.y
		_expect(top > 0.3 and top <= 0.91, "The range dome stays low over the floor (%.2f m)." % top)
	vfx.call("energy_shield")
	vfx.call("energy_shield")
	vfx.call("heartbeat", 0.2)
	var trail := DASH_TRAIL.start(stage, player, 0.15)
	_expect(trail != null, "Predator Dash leaves a trail.")
	var dash := player.create_tween()
	dash.tween_property(player, "global_position", Vector3(0, 0, -2), 0.15)
	await create_timer(2.0).timeout
	_expect(stage.get_child_count() == before, "One-shot effects free themselves.")
	_expect(not is_instance_valid(trail), "The dash trail fades and frees itself.")
	await _check_procedural(stage, player, effects, vfx)
	stage.queue_free()
	await process_frame
	print("Skill vfx tests: %d failure(s)." % failures)
	quit(failures)


# The self-made set behind the settings switch: same hooks, own nodes.
func _check_procedural(stage: Node3D, player: Node3D, effects: Node, vfx: Node) -> void:
	vfx.set("procedural", true)
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
	vfx.call("acid_pool", Vector3(2, 0, 0), 2.2, 0.3)
	vfx.call("spore_cocoon", Vector3(-2, 0, 0), 3.0, 0.2)
	# One node per cast plus range domes for the four area casts.
	_expect(stage.get_child_count() == before + 9, "Procedural casts appear in the world (%d)." % (stage.get_child_count() - before))
	vfx.set("_shield_ready", 0.0)
	vfx.call("energy_shield")
	vfx.call("heartbeat", 0.2)
	_expect(player.get_child_count() == player_before + 2, "Procedural shield and heart ride on the player.")
	for frame in 20:
		await process_frame
	await create_timer(1.6).timeout
	_expect(stage.get_child_count() == before, "Procedural casts free themselves.")
	_expect(player.get_child_count() == player_before, "Procedural shield and heart free themselves.")
	vfx.set("procedural", false)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
