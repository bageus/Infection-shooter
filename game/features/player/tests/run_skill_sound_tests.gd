extends SceneTree
## Skill sounds on the real player scene (ADR-0018): every active skill has a
## cast sound, lasting skills start their bed, ground-targeted skills sound at
## the aim point and Spore Cocoon bursts after its delay.

const PLAYER := preload("res://game/features/player/public/player.tscn")
const SFX := preload("res://game/core/audio/public/sound_events.gd")
## The twelve active skills of the mutation tree (mutation_catalog.gd ACTIVE).
const ACTIVE := ["blood_burst", "blood_burst_2", "blood_burst_3", "blood_infection", "discharge", "discharge_2", "discharge_3", "storm_pulse", "power_strike", "power_strike_2", "power_strike_3", "predator_dash", "active_claws", "active_claws_2", "active_claws_3", "berserk"]
const PLAYER_AUDIO := preload("res://game/features/player/player_audio.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for skill_id: String in ACTIVE:
		var spec: Array = PLAYER_AUDIO.SKILL_SOUNDS.get(skill_id, [])
		_expect(not spec.is_empty() and SFX.EVENTS.has(spec[0]), "Active skill has a cast sound: " + skill_id)
		_expect(spec.is_empty() or spec[1] == &"" or SFX.EVENTS.has(spec[1]), "Lasting sound exists: " + skill_id)
	for event in PLAYER_AUDIO.PASSIVE_SOUNDS.values():
		_expect(SFX.EVENTS.has(event), "Passive sound exists: " + String(event))
	_expect(PLAYER_AUDIO.SKILL_SOUNDS.size() == ACTIVE.size(), "No sounds for skills that do not exist.")

	var stage := Node3D.new()
	root.add_child(stage)
	var player := PLAYER.instantiate() as CharacterBody3D
	stage.add_child(player)
	player.set_physics_process(false)
	await process_frame
	var world := Node3D.new()
	stage.add_child(world)
	player.set("effects_root", world)
	player.global_position = Vector3(1, 0, 1)
	player.set("_aim_point", Vector3(6, 0, -3))
	var runtime: Node = player.get("infection_runtime")

	runtime.emit_signal("skill_cast", "storm_pulse")
	_expect(_voices(player, &"skill_storm_pulse") == 1 and _voices(player, &"skill_storm_field") == 1, "Storm Pulse casts and its field follows the player.")
	runtime.emit_signal("skill_cast", "power_strike_2")
	_expect(_voices(player, &"skill_bone_blades") == 1, "An upgraded power strike has its cast sound")
	runtime.emit_signal("passive_triggered", "retaliation", 0.0)
	_expect(_voices(player, &"skill_retaliation") == 1, "Retaliation's shock is heard.")
	runtime.emit_signal("passive_triggered", "regeneration", 0.0)
	_expect(_voices(player, &"skill_second_heart") == 0, "Quiet passives stay silent.")
	await _cooldown_feedback(player, runtime)
	stage.queue_free()
	await process_frame
	print("Skill sound tests: %d failure(s)." % failures)
	quit(failures)


func _cooldown_feedback(player: Node, runtime: Node) -> void:
	runtime.set_physics_process(false)
	var tree: RefCounted = runtime.get("tree")
	var domain: RefCounted = runtime.get("_domain")
	domain.set("mutation", 40.0)
	domain.set("critical_threshold", 45.0)
	tree.get("learned")["blood_burst"] = true
	runtime.call("assign_skill", 0, "blood_burst")
	runtime.call("_physics_process", .01)
	_expect(_voices(player, &"skill_cooldown_done") == 0, "Initially ready skills stay silent")
	_expect(runtime.call("cast_skill", "blood_burst"), "A learned skill starts its real cooldown")
	runtime.call("_physics_process", 1.0)
	_expect(_voices(player, &"skill_cooldown_done") == 0, "A running cooldown stays silent")
	runtime.call("_physics_process", 30.0)
	_expect(_voices(player, &"skill_cooldown_done") == 1, "Natural cooldown completion is heard once")
	runtime.call("_physics_process", .1)
	_expect(_voices(player, &"skill_cooldown_done") == 1, "Ready state does not repeat every frame")
	for child in player.get_children():
		if child.is_in_group(&"sfx_skill_cooldown_done"): child.queue_free()
	await process_frame
	_expect(runtime.call("cast_skill", "blood_burst"), "A ready skill can be cast again")
	runtime.call("reduce_skill_cooldowns", 100.0)
	_expect(_voices(player, &"skill_cooldown_done") == 1, "Accelerated completion uses the same cue")
	runtime.call("reduce_skill_cooldowns", 100.0)
	_expect(_voices(player, &"skill_cooldown_done") == 1, "Reduction never re-announces a ready skill")
	tree.get("cooldowns")["parasite"] = .1
	runtime.call("reduce_skill_cooldowns", 1.0)
	_expect(_voices(player, &"skill_cooldown_done") == 1, "Unlearned skill expiration stays silent")
	runtime.emit_signal("passive_triggered", "second_heart", 3.0)
	_expect(_voices(player, &"skill_second_heart") == 1, "Lethal-hit survival plays Done_alive")


func _voices(parent: Node, event: StringName) -> int:
	var count := 0
	for child in parent.get_children():
		if child.is_in_group(StringName("sfx_" + String(event))):
			count += 1
	return count


func _first(parent: Node, event: StringName) -> Node3D:
	for child in parent.get_children():
		if child.is_in_group(StringName("sfx_" + String(event))):
			return child as Node3D
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
