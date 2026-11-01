extends SceneTree
const PLAYER := preload("res://game/features/player/public/player.tscn")
const HUD_SCENE := preload("res://game/presentation/prototype_hud/public/prototype_hud.tscn")
const TREE_UI := preload("res://game/bootstrap/app/mutation_tree_ui.gd")
const DIRECTOR := preload("res://game/bootstrap/app/tutorial/tutorial_director.gd")
const PROGRESS := preload("res://game/bootstrap/app/tutorial/tutorial_progress.gd")
const LOCALIZATION := preload("res://game/core/localization/public/ui_translations.gd")
const TEXT := preload("res://game/bootstrap/app/mutation_text.gd")
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
	var seen := PROGRESS.new(SAVE)
	for first_run in ["move", "shoot", "look", "one_way", "roll", "explore", "crates", "weapons", "armor"]:
		seen.mark_done(first_run) # the first-run chain has its own test
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
	_check(str(overlay.get("step").get("text")) == TEXT.t("tutInhale") and paused, "The inhale task opens as a full-screen paused overlay")
	await _advance(overlay)
	_check(not paused and str(overlay.get("step").get("objective")) == TEXT.t("objInhale"), "Then it becomes the objective and the game runs")
	_check(not TEXT.t("tutAntidoteWise").is_empty() and not "tutKillActive" in TEXT.t("tutKillActive"), "Lesson texts resolve")
	_check(not "мутаген и откро" in TEXT.t("tutKillActive") and not "absorb mutagen" in TEXT.t("tutKillActive"), "The kill hint no longer promises mutagen and a skill")
	await process_frame
	await process_frame
	_check(director.get("current") == "" and not paused, "With no cloud left the inhale task is done")
	_check(PROGRESS.new(SAVE).is_done("mutation_scale"), "The lesson is remembered")

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
	_check(str(overlay.get("step").get("mode")) == "click" and paused, "Learning it opens the kill task as a paused overlay")
	await _advance(overlay)
	_check(str(overlay.get("step").get("objective")) != "", "The kill task then waits as the objective")
	await _passive_lesson(director, overlay, runtime)

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
	await _menu_lessons(director, overlay, hud, tree_ui)
	_check(not paused, "Nothing stays paused")

	await _door_passage(director, actor)
	await _replay_level(director, overlay)
	await _mask_hud(hud, runtime)
	# The HUD owns audio players that hold their streams; free it so nothing is still in use at exit.
	for sound: AudioStreamPlayer in hud.find_children("*", "AudioStreamPlayer", true, false):
		sound.stop()
	await create_timer(0.3).timeout # the audio thread lets go of a stopped stream a moment later
	director.free() # its lessons hold callables bound to the HUD
	hud.queue_free()
	await create_timer(0.3).timeout
	DirAccess.remove_absolute(SAVE)
	if failures == 0:
		print("Tutorial tests passed.")
	else:
		push_error("Tutorial tests failed: %d failure(s)." % failures)
	quit(failures)


func _passive_lesson(director: Node, overlay: Node, runtime: Node) -> void:
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


func _menu_lessons(director: Node, overlay: Node, hud: Node, tree_ui: Node) -> void:
	_check(director.get("current") == "open_menu", "After the antidote lesson the M menu lesson follows")
	_check(str(overlay.get("step").get("mode")) == "click", "It first asks to press M on a paused overlay")
	await _advance(overlay)
	_check(not paused and str(overlay.get("step").get("objective")) != "", "Then it waits for the menu as the objective")
	tree_ui.call("open_tree")
	await process_frame
	await process_frame
	_check(not tree_ui.call("tutorial_rect", "passive").size.is_zero_approx() and str(overlay.get("step").get("mode")) == "wait",
			"With the menu open the passive group is highlighted")
	tree_ui.call("close_tree")
	await process_frame
	await process_frame
	_check(director.get("current") == "gas_mask", "Then the gas mask lesson")
	_check(not hud.call("tutorial_rect", "gas_mask").size.is_zero_approx(), "It spotlights the gas mask icon")
	await _advance(overlay)
	_check(director.get("current") == "", "The gas mask lesson ends")


# "Walk through the door" counts only when the hero ends up on the other side of the opening.
func _door_passage(director: Node, actor: Node3D) -> void:
	var door := Node3D.new()
	var frame := Node3D.new()
	frame.name = "DoorController"
	door.add_child(frame)
	root.add_child(door)
	door.global_position = Vector3(40, 0, 40)
	var passed: Callable = director.call("_through", [door])
	actor.global_position = Vector3(40, 0, 37.5)
	_check(not passed.call(), "Standing in front of the door is not passing it")
	actor.global_position = Vector3(40, 0, 39.9)
	_check(not passed.call(), "Touching the door plane is not passing it")
	actor.global_position = Vector3(46, 0, 42.5) # round the wall, far to the side
	passed.call()
	actor.global_position = Vector3(40, 0, 42.5)
	_check(not passed.call(), "Coming round the wall to the far side is not passing the door")
	passed = director.call("_through", [door])
	actor.global_position = Vector3(40, 0, 37.5)
	passed.call()
	actor.global_position = Vector3(40, 0, 42.5)
	_check(passed.call(), "Walking from one side to the other passes the door")
	door.free()


# On tutorial_lvl a lesson shows again even though the saved flags say it was seen.
func _replay_level(director: Node, overlay: Node) -> void:
	var host := Node.new()
	host.set_script(GDScript.new())
	director.set("_host", host)
	director.call("request", "gas_mask")
	_check(director.get("current") == "", "Another level keeps a seen lesson hidden")
	host.free()
	var level := Node.new()
	var script := GDScript.new()
	script.source_code = "extends Node\nvar current_level := \"tutorial_lvl\"\n"
	script.reload()
	level.set_script(script)
	director.set("_host", level)
	director.get("_finished").erase("gas_mask")
	director.call("request", "gas_mask")
	_check(director.get("current") == "gas_mask", "tutorial_lvl replays a lesson already marked seen")
	await _advance(overlay)
	director.set("_host", null)
	level.free()


func _mask_hud(hud: Node, runtime: Node) -> void:
	var domain = runtime.get("_domain")
	domain.mutation = 0.0
	domain.control_loss_remaining = 0.0
	domain.defeated = false
	domain.gas_mask_cooldown_remaining = 0.0
	var icon: Control = hud.get_node("GasMaskPanel/Icon")
	await process_frame
	_check(is_equal_approx(icon.modulate.a, 1.0), "A taken-off mask shows a bright icon")
	runtime.call("put_on_gas_mask")
	await process_frame
	_check(icon.modulate.a < 0.5, "A worn mask shows a dark icon")
	domain.gas_mask_worn_remaining = 0.0
	domain.tick(0.0)
	await process_frame
	_check((hud.get_node("GasMaskPanel/Cooldown") as Label).text == "120", "The panel counts the 120 s cooldown after the mask comes off")


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
