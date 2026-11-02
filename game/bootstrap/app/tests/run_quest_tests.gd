extends SceneTree
const MODEL := preload("res://game/bootstrap/app/quest/quest_model.gd")
const LOGIC := preload("res://game/bootstrap/app/quest/quest_logic.gd")
const BOOK := preload("res://game/bootstrap/app/quest/quest_book.gd")
const RUNNER := preload("res://game/bootstrap/app/quest/quest_runner.gd")
const STORE := preload("res://game/bootstrap/app/quest/quest_store.gd")
const VALIDATOR := preload("res://game/bootstrap/app/planning_layout_validator.gd")
const TARGET := preload("res://game/presentation/office_floor/public/tutorial_target.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_model()
	_logic()
	_book()
	await _runner()
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
	for lesson in MODEL.lesson_ids():
		_check('\t\t"%s":' % lesson in director_source, "Lesson %s exists in the director" % lesson)
	for lesson in ["move", "look", "roll", "sprint", "shoot", "reload", "mutation_scale", "active_skill", "passive_skill", "gas_mask", "antidote", "crates", "dna", "armor", "weapons", "one_way", "explore", "control_loss", "open_menu"]:
		_check(lesson in MODEL.lesson_ids(), "Lesson %s is in the picker" % lesson)
	var messy := MODEL.normalize({"type": "bogus", "delay": -5, "targets": ["a", "a", "", "b"], "trigger": {"kind": "xx", "value": 9.0}, "text": "hi"})
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
	runner.configure(book, player, hud, null, null)
	var find := MODEL.make("find")
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
	player.global_position = Vector3(9, 0, 0)
	await process_frame
	await process_frame
	_check(runner.index == 1 and not (prop.get_meta(&"planning_tutorial_revealed", false) == true), "Reaching the target ends it and hides the marker")
	_check(hud.text == "", "The second quest waits for its time trigger")
	await create_timer(0.5).timeout
	_check(hud.text == "Second" and runner.index == 1, "The time trigger starts the next quest")
	book.restore([MODEL.make("message")])
	await process_frame
	_check(runner.index == 0, "Loading new quests restarts the sequence")
	runner.free()
	book.free()
	hud.free()
	prop.free()
	player.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("ok: ", message)
