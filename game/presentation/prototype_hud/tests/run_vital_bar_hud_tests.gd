extends SceneTree
const PLAYER := preload("res://game/features/player/public/player.tscn")
const HUD := preload("res://game/presentation/prototype_hud/public/prototype_hud.tscn")
const UI := preload("res://game/core/localization/public/ui_translations.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var player := PLAYER.instantiate() as Node3D
	player.name = "Player"
	stage.add_child(player)
	player.set_physics_process(false)
	var infection := player.get_node("InfectionRuntime")
	infection.set_physics_process(false)
	var hud := HUD.instantiate()
	hud.set("player_path", NodePath("../Player"))
	stage.add_child(hud)
	hud.set_process(false)
	hud.call("_process", 0.0)
	var health = hud.get("_health_feedback")
	var mutation = hud.get("_mutation_feedback")
	_check(health.state.displayed == 100 and mutation.state.displayed == 0, "Both real HUD bars initialize without a load-time pulse")
	player.set("health", 85.0)
	infection.call("absorb_mutagen", 1.0)
	var actual_mutation: float = infection.call("get_mutation")
	hud.call("_process", 0.02)
	_check(hud.get("hp_bar").value == 85 and hud.get("mutation_bar").value == actual_mutation, "Real health and mutation fills update immediately")
	_check(health.state.displayed == 99 and mutation.state.displayed == 1, "Both counters advance by one while actual gameplay values stay authoritative")
	_check(health.state.pulse_scale < 1 and mutation.state.pulse_scale > 1, "Damage shrinks health while mutation growth enlarges its indicator")
	for i in 120:
		hud.call("_process", 0.02)
	_check(health.state.displayed == 85 and mutation.state.displayed == roundi(actual_mutation), "Animation continues after HUD snapshot stops changing")
	_check(not health.state.active() and not mutation.state.active(), "Idle bars finish their animation and stop redraw work")
	player.set("health", 95.0)
	_check(infection.call("use_antidote"), "Real antidote reduces the mutation value")
	hud.call("_process", 0.14)
	_check(is_equal_approx(health.state.pulse_scale, 1.05) and is_equal_approx(mutation.state.pulse_scale, 0.95), "Healing enlarges health and antidote shrinks mutation at their exact five-percent peaks")
	_check(hud.get("armor_bar").scale == Vector2.ONE and hud.get("armor_bar").value == player.get("armor"), "Armor presentation is not animated by either effect")
	UI.apply_language("ru")
	hud.call("_process", 0.0)
	_check(health.state.target == 95 and mutation.state.target == infection.call("get_mutation"), "Locale refresh preserves existing animation targets")
	player.set("max_health", 140.0)
	hud.call("_process", 0.0)
	_check(hud.get("hp_value").text == "95 / 140" and health.state.pulse_scale == 1, "Changing maximum health safely re-syncs the counter and pulse")
	# Check the real processing lifecycle rather than manually advancing while paused.
	hud.set_process(true)
	player.set("health", 70.0)
	hud.call("_process", 0.02)
	paused = true
	var held: int = health.state.displayed
	await create_timer(0.15, true).timeout
	_check(health.state.displayed == held, "Paused HUD cannot consume the numeric animation")
	paused = false
	hud.set_process(false)
	stage.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.3).timeout
	print("Vital bar HUD tests: %d failures" % failures)
	quit(1 if failures else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
