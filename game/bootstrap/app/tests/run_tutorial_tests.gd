extends SceneTree
const PLAYER := preload("res://game/features/player/public/player.tscn")
const HUD_SCENE := preload("res://game/presentation/prototype_hud/public/prototype_hud.tscn")
const TREE_UI := preload("res://game/bootstrap/app/mutation_tree_ui.gd")
const DIRECTOR := preload("res://game/bootstrap/app/tutorial/tutorial_director.gd")
const PROGRESS := preload("res://game/bootstrap/app/tutorial/tutorial_progress.gd")
const LOCALIZATION := preload("res://game/core/localization/public/ui_translations.gd")
const SAVE := "user://tutorial_test.cfg"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	LOCALIZATION.apply_language("en")
	DirAccess.remove_absolute(SAVE)
	var actor := PLAYER.instantiate()
	actor.name = "Player"
	root.add_child(actor)
	actor.set_physics_process(false)
	var runtime: Node = actor.get("infection_runtime")
	runtime.set_physics_process(false)
	var hud := HUD_SCENE.instantiate()
	hud.set("player_path", NodePath("../Player"))
	root.add_child(hud)
	var tree_ui := TREE_UI.new()
	root.add_child(tree_ui)
	tree_ui.call("configure", runtime)
	var director := DIRECTOR.new()
	root.add_child(director)
	director.call("configure", actor, hud, tree_ui, PROGRESS.new(SAVE))
	var overlay: Node = director.get("overlay")
	await process_frame

	_check(not bool(overlay.get("active")), "No lesson before mutation grows")
	runtime.get("_domain").mutation = 5.0
	runtime.call("absorb_mutagen", 0.01)
	await process_frame
	_check(director.get("current") == "mutation_scale" and bool(overlay.get("active")), "Mutation 5 starts the scale lesson")
	_check(paused, "A click step pauses the game")
	_check(not hud.call("tutorial_rect", "mutation").size.is_zero_approx(), "The scale lesson spotlights the HUD bar")
	await _advance(overlay)
	_check(bool(overlay.get("picture").visible), "The second step shows the scale picture")
	await _advance(overlay)
	await _advance(overlay)
	await _advance(overlay)
	_check(director.get("current") == "" and not paused, "The scale lesson ends and unpauses")
	_check(PROGRESS.new(SAVE).is_done("mutation_scale"), "The finished lesson is remembered")

	runtime.get("_domain").mutation = 25.0
	runtime.call("absorb_mutagen", 0.01)
	await process_frame
	_check(director.get("current") == "active_skill" and bool(tree_ui.call("is_tree_open")), "A first skill point opens the tree lesson")
	await process_frame
	_check(not tree_ui.call("tutorial_rect", "active").size.is_zero_approx(), "The tree exposes the active group rectangle")
	_check(not tree_ui.call("tutorial_rect", "skill:power_strike").size.is_zero_approx(), "The tree exposes the Power Strike circle")
	for i in 3:
		await _advance(overlay)
	_check(str(overlay.get("step").get("mode")) == "wait", "Choosing Power Strike is a wait step")
	runtime.call("upgrade_skill", "power_strike")
	await process_frame
	await process_frame
	_check(bool(overlay.get("step").get("hint")), "Learning it shows the kill hint")
	runtime.get("_domain").mutation = 29.99
	runtime.call("absorb_mutagen", 0.002)
	await process_frame
	await process_frame
	_check(director.get("current") == "passive_skill", "The next point starts the passive lesson")
	runtime.call("upgrade_skill", "muscle_memory")
	await process_frame
	await process_frame
	_check(str(overlay.get("step").get("mode")) == "click", "The lock explanation follows learning the passive skill")
	await _advance(overlay)
	_check(director.get("current") == "", "The passive lesson ends")

	tree_ui.call("close_tree")
	runtime.get("_domain").mutation = 40.0
	runtime.get("_domain").control_loss_remaining = 2.0
	runtime.get("_domain").active_control_loss_stage = 1
	runtime.call("absorb_mutagen", 0.0)
	await process_frame
	_check(director.get("current") == "control_loss" or PROGRESS.new(SAVE).is_done("control_loss") == false, "Control loss starts its lesson")
	await _advance(overlay)
	_check(str(overlay.get("step").get("mode")) == "wait", "Then it waits for the antidote")
	actor.call("use_antidote")
	await process_frame
	await process_frame
	await _advance(overlay)
	_check(not hud.call("tutorial_rect", "gas_mask").size.is_zero_approx(), "The last step spotlights the gas mask icon")
	await _advance(overlay)
	_check(director.get("current") == "", "The control loss lesson ends")
	_check(not paused, "Nothing stays paused")

	await _mask_hud(hud, runtime)
	# The HUD owns audio players that hold their streams; free it so nothing is still in use at exit.
	hud.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(SAVE)
	if failures == 0:
		print("Tutorial tests passed.")
	else:
		push_error("Tutorial tests failed: %d failure(s)." % failures)
	quit(failures)


func _mask_hud(hud: Node, runtime: Node) -> void:
	var domain = runtime.get("_domain")
	domain.mutation = 0.0
	domain.control_loss_remaining = 0.0
	domain.defeated = false
	domain.gas_mask_cooldown_remaining = 0.0
	var icon: Control = hud.get_node("GasMaskPanel/Icon")
	await process_frame
	_check(is_equal_approx(icon.modulate.a, 1.0), "A taken-off mask shows a bright icon")
	runtime.call("toggle_gas_mask")
	await process_frame
	_check(icon.modulate.a < 0.5, "A worn mask shows a dark icon")
	_check((hud.get_node("GasMaskPanel/Cooldown") as Label).text == "60", "The panel counts the cooldown down")


# Waits out the short guard against accidental skips, then presses a key.
func _advance(overlay: Node) -> void:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 400:
		await process_frame
	var press := InputEventKey.new()
	press.keycode = KEY_SPACE
	press.pressed = true
	overlay.call("_input", press)
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("ok: ", message)
