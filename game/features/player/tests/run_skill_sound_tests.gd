extends SceneTree
## Skill sounds on the real player scene (ADR-0018): every active skill has a
## cast sound, lasting skills start their bed, ground-targeted skills sound at
## the aim point and Spore Cocoon bursts after its delay.

const PLAYER := preload("res://game/features/player/public/player.tscn")
const SFX := preload("res://game/core/audio/public/sound_events.gd")
## The twelve active skills of the mutation tree (mutation_catalog.gd ACTIVE).
const ACTIVE := ["blood_burst", "parasite", "living_harvest", "discharge", "overload", "storm_pulse",
	"acid_spit", "spore_cocoon", "epidemic", "predator_dash", "bone_blades", "berserk"]
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
	runtime.emit_signal("skill_cast", "acid_spit")
	_expect(_voices(player, &"skill_acid_spit") == 1, "Acid Spit is heard from the player.")
	var sizzle := _first(world, &"acid_sizzle")
	_expect(sizzle != null and sizzle.global_position.is_equal_approx(Vector3(6, 0, -3)), "The acid pool sizzles where it landed.")
	runtime.emit_signal("skill_cast", "spore_cocoon")
	var pod := _first(world, &"skill_spore_cocoon")
	_expect(pod != null and pod.global_position.is_equal_approx(Vector3(6, 0, -3)), "The spore pod lands at the aim point.")
	player.set("_aim_point", Vector3(-4, 0, 0))
	await create_timer(PLAYER_AUDIO.SPORE_DELAY + 0.2).timeout
	var burst := _first(world, &"spore_burst")
	_expect(burst != null and burst.global_position.is_equal_approx(Vector3(6, 0, -3)), "Spores burst at the pod after the delay, not at the new aim.")
	runtime.emit_signal("passive_triggered", "retaliation", 0.0)
	_expect(_voices(player, &"skill_retaliation") == 1, "Retaliation's shock is heard.")
	runtime.emit_signal("passive_triggered", "regeneration", 0.0)
	_expect(_voices(player, &"skill_second_heart") == 0, "Quiet passives stay silent.")
	stage.queue_free()
	await process_frame
	print("Skill sound tests: %d failure(s)." % failures)
	quit(failures)


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
