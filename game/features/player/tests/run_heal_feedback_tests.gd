extends SceneTree
## Healing feedback: medkit pickups burst and show a floating +HP number,
## continuous healing is summed into occasional numbers, full health shows
## nothing, and every spawned effect frees itself.

const IMPACTS := preload("res://game/features/combat/public/impact_effects.gd")
const PLAYER := preload("res://game/features/player/public/player.tscn")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var player := PLAYER.instantiate() as CharacterBody3D
	stage.add_child(player)
	var impacts := Node3D.new()
	impacts.set_script(IMPACTS)
	stage.add_child(impacts)
	player.call("configure_world", stage, impacts)
	player.set("gravity_acceleration", 0.0)
	var feedback := player.get_node("HealFeedback") as Node3D
	var events: Array = []
	player.connect("healed", func(amount: float, source: StringName) -> void: events.append([amount, source]))

	player.call("heal", 20.0, &"medkit")
	await process_frame
	_expect(events.is_empty(), "Full health emits no heal event.")
	_expect(_numbers(feedback).is_empty(), "Full health shows no heal number.")
	await _test_medkit_and_regen(player, feedback, events)
	stage.queue_free()
	await process_frame
	if failures == 0:
		print("Heal feedback tests passed.")
	quit(failures)


func _test_medkit_and_regen(player: Node3D, feedback: Node3D, events: Array) -> void:

	player.set("armor", 0.0)
	player.call("take_damage", 40.0)
	# Medkit pickups call heal(amount, &"medkit") on the collector.
	var amount := 20.0
	player.call("heal", amount, &"medkit")
	await process_frame
	_expect(events.size() == 1 and is_equal_approx(float(events[0][0]), amount) and events[0][1] == &"medkit", "Medkit pickup reports the restored amount with the medkit source.")
	var numbers := _numbers(feedback)
	_expect(numbers.size() == 1 and numbers[0].text == "+%d" % floori(amount), "Medkit pickup shows the restored HP as a floating number.")
	_expect(feedback.get_node_or_null("HealRing") != null and feedback.get_node_or_null("HealBurst") != null and feedback.get_node_or_null("HealLight") != null, "Medkit pickup plays the floor ring, cross burst and light flash.")
	_expect(bool((feedback.get_node("HealSparkles") as CPUParticles3D).emitting), "Healing turns on the rising sparkles.")
	var start_y: float = numbers[0].position.y
	for frame in range(20):
		await process_frame
	_expect(is_instance_valid(numbers[0]) and numbers[0].position.y > start_y, "The HP number rises.")

	# Regeneration-sized heals are summed instead of spawning a number per frame.
	await _wait_until_clear(feedback)
	for tick in range(30):
		player.call("heal", 0.11)
	await process_frame
	_expect(_numbers(feedback).is_empty(), "Tiny heals are summed before a number appears.")
	await create_timer(1.0).timeout
	var regen_numbers := _numbers(feedback)
	_expect(regen_numbers.size() == 1 and regen_numbers[0].text == "+3", "Summed healing shows one number for the restored total.")

	await _wait_until_clear(feedback)
	_expect(_numbers(feedback).is_empty() and feedback.get_node_or_null("HealRing") == null and feedback.get_node_or_null("HealLight") == null and feedback.get_node_or_null("HealBurst") == null, "Heal effects free themselves.")
	_expect(not bool((feedback.get_node("HealSparkles") as CPUParticles3D).emitting), "Sparkles stop once healing ends.")


func _numbers(feedback: Node) -> Array[Label3D]:
	var found: Array[Label3D] = []
	for child in feedback.get_children():
		if child is Label3D and not child.is_queued_for_deletion():
			found.append(child)
	return found


func _wait_until_clear(feedback: Node) -> void:
	for attempt in range(200):
		if _numbers(feedback).is_empty() and feedback.get_child_count() == 1:
			return
		await create_timer(0.05).timeout


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
