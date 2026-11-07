extends SceneTree
const MODEL := preload("res://game/bootstrap/app/quest/quest_model.gd")
const LOGIC := preload("res://game/bootstrap/app/quest/quest_logic.gd")
const BOOK := preload("res://game/bootstrap/app/quest/quest_book.gd")
const RUNNER := preload("res://game/bootstrap/app/quest/quest_runner.gd")
const STORE := preload("res://game/bootstrap/app/quest/quest_store.gd")
const VALIDATOR := preload("res://game/bootstrap/app/planning_layout_validator.gd")
const TARGET := preload("res://game/presentation/office_floor/public/tutorial_target.gd")
const ENEMY_LESSONS := preload("res://game/bootstrap/app/tutorial/tutorial_enemy_lessons.gd")
const UI_TRANSLATIONS := preload("res://game/core/localization/public/ui_translations.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_model()
	_logic()
	_book()
	await _runner()
	await _menu_while_paused()
	await _language_switch()
	if failures == 0:
		print("Quest tests passed.")
	else:
		push_error("Quest tests failed: %d failure(s)." % failures)
	quit(failures)


func _model() -> void:
	var quest := MODEL.make("lesson", "dna")
	_check(quest.text == "Базовое обучение: ДНК" and quest.lesson == "dna", "A lesson quest starts with its preset text")
	_check(MODEL.make("kill").complete.kind == "destroy" and MODEL.make("pickup").complete.kind == "collect", "Each type has a default completion")
	_check(MODEL.make("find").delay == 0.0 and MODEL.make("find").trigger.kind == "previous", "Delay is 0 and the trigger is the previous quest by default")
	var director_source := FileAccess.get_file_as_string("res://game/bootstrap/app/tutorial/tutorial_director.gd")
	var enemy_lessons := ENEMY_LESSONS.ids()
	for lesson in MODEL.lesson_ids():
		if lesson in enemy_lessons:
			_check(ENEMY_LESSONS.has(lesson), "Enemy lesson %s has its text and preview" % lesson)
			continue
		_check('\t\t"%s":' % lesson in director_source, "Lesson %s exists in the director" % lesson)
	for lesson in ["move", "look", "roll", "sprint", "shoot", "reload", "mutation_scale", "active_skill", "passive_skill", "gas_mask", "antidote", "crates", "dna", "armor", "weapons", "one_way", "explore", "control_loss", "open_menu"]:
		_check(lesson in MODEL.lesson_ids(), "Lesson %s is in the picker" % lesson)
	var messy := MODEL.normalize({"type": "bogus", "delay": -5, "targets": ["a", "a", "", "b"], "trigger": {"kind": "xx", "value": 9.0}, "text": "hi"})
	var rise := MODEL.make("find")
	rise.trigger = {"kind": "mutation_rise", "value": 2.0, "target": "", "point": []}
	_check(not LOGIC.trigger_ready(rise, {"mutation_gain": 1.5}) and LOGIC.trigger_ready(rise, {"mutation_gain": 2.0}), "The mutation rise trigger waits for the meter to climb")
	var menu := MODEL.make("find")
	menu.trigger.kind = "menu_open"
	_check(not LOGIC.trigger_ready(menu, {}) and LOGIC.trigger_ready(menu, {"menu_open": true}), "The menu trigger waits for the menu")
	var lost := MODEL.make("find")
	lost.trigger.kind = "control_lost"
	_check(not LOGIC.trigger_ready(lost, {}) and LOGIC.trigger_ready(lost, {"control_lost": true}), "The control loss trigger waits for the loss")
	var taken := MODEL.make("find")
	taken.trigger.kind = "collect"
	_check(not LOGIC.trigger_ready(taken, {}) and LOGIC.trigger_ready(taken, {"trigger_collected": true}), "The collect trigger waits for the object to be taken")
	var leave := MODEL.make("leave")
	_check(leave.complete.kind == "" and leave.text.contains("лестниц"), "A leave quest has its own preset text")
	_check(not LOGIC.complete(leave, {}) and LOGIC.complete(leave, {"left_level": true}), "A leave quest is done when the level is left")
	_check(MODEL.normalize({"trigger": {"kind": "control_lost"}}).trigger.kind == "control_lost", "The new trigger kinds survive normalizing")
	_check(not MODEL.make("find").pointer and MODEL.normalize({"pointer": true}).pointer, "The pointer flag defaults off and survives normalizing")
	_check(messy.type == "find" and messy.delay == 0.0 and messy.targets == ["a", "b"] and messy.trigger.kind == "previous", "Normalizing repairs bad values")
	_check(messy.text == "hi", "A custom description survives")
	_check(MODEL.error([{"type": "find"}]).is_empty() and not MODEL.error([{"type": "nope"}]).is_empty() and not MODEL.error("x").is_empty(), "The map validator checks the list")
	_check(VALIDATOR.error({"version": 8, "objects": [], "quests_v1": "bad"}) != "", "A bad list rejects the map")


func _logic() -> void:
	var timed := MODEL.normalize({"type": "find", "trigger": {"kind": "time", "value": 5.0}})
	_check(not LOGIC.trigger_ready(timed, {"idle": 4.0}) and LOGIC.trigger_ready(timed, {"idle": 5.0}), "Time trigger")
	var stepped := MODEL.normalize({"type": "find", "trigger": {"kind": "steps", "value": 10.0}})
	_check(not LOGIC.trigger_ready(stepped, {"steps": 9.0}) and LOGIC.trigger_ready(stepped, {"steps": 10.0}), "Steps trigger")
	var reach := MODEL.normalize({"type": "find", "trigger": {"kind": "reach"}})
	_check(not LOGIC.trigger_ready(reach, {"reach": 6.0}) and LOGIC.trigger_ready(reach, {"reach": 1.5}), "Reach trigger")
	_check(LOGIC.trigger_ready(MODEL.make("find"), {}), "The previous-quest trigger is ready at once")
	var find := MODEL.make("find")
	_check(not LOGIC.complete(find, {"distances": [5.0, 1.0], "gone": [false, false]}) and LOGIC.complete(find, {"distances": [1.0, 1.5], "gone": [false, false]}), "Reach completes next to every target")
	_check(LOGIC.complete(MODEL.make("kill"), {"gone": [true, true]}) and not LOGIC.complete(MODEL.make("kill"), {"gone": [true, false]}), "Destroy needs every target gone")
	var walk := MODEL.normalize({"type": "find", "complete": {"kind": "steps", "value": 20.0}})
	_check(not LOGIC.complete(walk, {"steps": 19.0}) and LOGIC.complete(walk, {"steps": 20.0}), "Steps completion")
	_check(not LOGIC.complete(MODEL.make("lesson", "move"), {"lesson_done": false}) and LOGIC.complete(MODEL.make("lesson", "move"), {"lesson_done": true}), "A lesson quest ends with its lesson")


func _book() -> void:
	var book := BOOK.new()
	book.add("find")
	book.add("message")
	book.add("lesson", "armor")
	_check(book.quests.size() == 3, "Quests are added in order")
	book.move(2, -1)
	_check(book.quests[1].type == "lesson", "A quest moves up")
	book.quests[0].targets = ["object_1"]
	_check(book.quests_using("object_1") == [1] and book.quests_using("object_9").is_empty(), "A target knows which quests use it")
	var saved: Array = book.capture()
	var other := BOOK.new()
	other.restore(saved)
	_check(other.quests == saved, "Capture and restore round-trip")
	other.restore([])
	_check(other.quests.is_empty(), "A map without quests clears the list")
	book.remove(0)
	_check(book.quests.size() == 2, "A quest is removed")
	book.free()
	other.free()


## A preset quest text follows the language, also when the language changes while the banner shows it.
func _language_switch() -> void:
	UI_TRANSLATIONS.apply_language("en")
	_check(MODEL.display_text("Найдите цель") == "Find the target", "A preset quest text is shown in English")
	_check(MODEL.display_text("Свой текст задания") == "Свой текст задания", "An authored quest text is shown as written")
	var hud := Node.new()
	var script := GDScript.new()
	script.source_code = "extends Node\nvar text := \"\"\nfunc set_tutorial_objective(value: String) -> void:\n\ttext = value\n"
	script.reload()
	hud.set_script(script)
	root.add_child(hud)
	var runner = RUNNER.new()
	runner.hud = hud
	root.add_child(runner)
	runner._set_objective("Найдите цель")
	_check(hud.text == "Find the target", "The banner shows the preset in the current language")
	UI_TRANSLATIONS.apply_language("ru")
	await process_frame
	_check(hud.text == "Найдите цель", "The banner switches to Russian when the language changes")
	UI_TRANSLATIONS.apply_language("en")
	await process_frame
	_check(hud.text == "Find the target", "The banner switches to English when the language changes")
	runner.free()
	hud.free()


func _runner() -> void:
	var player := Node3D.new()
	root.add_child(player)
	var hud := Node.new()
	var script := GDScript.new()
	script.source_code = "extends Node\nvar text := \"\"\nfunc set_tutorial_objective(value: String) -> void:\n\ttext = value\n"
	script.reload()
	hud.set_script(script)
	root.add_child(hud)
	var prop := Node3D.new()
	prop.set_meta(&"planning_scene_path", "res://x.tscn")
	root.add_child(prop)
	prop.global_position = Vector3(10, 0, 0)
	TARGET.configure(prop, true)
	var id := str(prop.get_meta(&"planning_object_id", ""))
	_check(not id.is_empty() and TARGET.is_target(prop), "Flagging an object gives it an id for quests")
	var book := BOOK.new()
	root.add_child(book)
	var runner := RUNNER.new()
	root.add_child(runner)
	var host := Node.new()
	var host_script := GDScript.new()
	host_script.source_code = "extends Node\nvar hint := Callable()\nfunc set_tutorial_hint(target: Callable) -> void:\n\thint = target\n"
	host_script.reload()
	host.set_script(host_script)
	root.add_child(host)
	runner.configure(book, player, hud, null, host)
	var find := MODEL.make("find")
	find.pointer = true
	find.targets = [id]
	find.text = "Go to the box"
	var wait := MODEL.make("find")
	wait.trigger = {"kind": "time", "value": 0.2, "target": "", "point": []}
	wait.complete = {"kind": "steps", "value": 1000.0}
	wait.text = "Second"
	book.restore([find, wait])
	await process_frame
	await process_frame
	_check(hud.text == "Go to the box" and runner.index == 0, "The first quest shows its text")
	_check(prop.get_meta(&"planning_tutorial_revealed", false) == true, "Its target marker is revealed")
	_check(host.hint.is_valid() and host.hint.call() == Vector3(10, 0, 0), "A quest with a pointer leads the floor chevrons to its target")
	player.global_position = Vector3(9, 0, 0)
	await process_frame
	await process_frame
	_check(runner.index == 1 and not (prop.get_meta(&"planning_tutorial_revealed", false) == true), "Reaching the target ends it and hides the marker")
	_check(not host.hint.is_valid(), "The pointer disappears when the quest is done")
	_check(hud.text == "", "The second quest waits for its time trigger")
	await create_timer(0.5).timeout
	_check(hud.text == "Second" and runner.index == 1, "The time trigger starts the next quest")
	book.restore([MODEL.make("message")])
	await process_frame
	_check(runner.index == 0, "Loading new quests restarts the sequence")
	runner.free()
	host.free()
	book.free()
	hud.free()
	prop.free()
	player.free()


# The mutation menu pauses the game; the quest waiting for it must still see it open.
func _menu_while_paused() -> void:
	var player := Node3D.new()
	root.add_child(player)
	var host := Node.new()
	var script := GDScript.new()
	script.source_code = "extends Node\nvar mutation_tree_ui := self\nvar open := false\nfunc is_tree_open() -> bool:\n\treturn open\nfunc set_tutorial_objective(_value: String) -> void:\n\tpass\n"
	script.reload()
	host.set_script(script)
	root.add_child(host)
	var book := BOOK.new()
	root.add_child(book)
	var runner := RUNNER.new()
	root.add_child(runner)
	runner.configure(book, player, host, null, host)
	var open_menu := MODEL.make("message")
	open_menu.trigger = {"kind": "menu_open", "value": 0.0, "target": "", "point": []}
	book.restore([open_menu])
	await process_frame
	_check(runner.phase == runner.Phase.TRIGGER, "A quest waits for the menu")
	paused = true
	host.open = true
	await process_frame
	await process_frame
	paused = false
	_check(runner.phase != runner.Phase.TRIGGER, "The menu trigger fires although the menu paused the game")
	runner.free()
	host.free()
	book.free()
	player.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("ok: ", message)
