extends SceneTree
const PLAYER := preload("res://game/features/player/public/player.tscn")
const TREE_UI := preload("res://game/bootstrap/app/mutation_tree_ui.gd")
const TEXT := preload("res://game/bootstrap/app/mutation_text.gd")
const LOCALIZATION := preload("res://game/core/localization/public/ui_translations.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	LOCALIZATION.apply_language("en")
	var actor := PLAYER.instantiate()
	root.add_child(actor)
	actor.set_physics_process(false)
	var runtime: Node = actor.get("infection_runtime")
	runtime.set_physics_process(false)
	runtime.get("_domain").mutation = 30.0
	_check(runtime.call("upgrade_skill", "muscle_memory"), "Fixture learns a real skill")
	var stock: int = actor.get("antidotes")
	# Ordinary use that forgets a skill applies at once, without a prompt or pause.
	_check(actor.call("use_antidote") and not paused, "Ordinary skill loss applies without a confirmation")
	_check(actor.get("antidotes") == stock - 1 and runtime.call("get_mutation") == 20.0, "Ordinary use spends exactly one dose")
	_check(runtime.call("mutation_points") == 0 and not runtime.call("skill_learned", "muscle_memory"), "Forgotten skill point leaves with the budget at the new mutation")
	# Emergency use with an active loss is immediate as well.
	runtime.get("_domain").mutation = 30.1
	runtime.get("_domain").control_loss_remaining = 2.0
	runtime.get("_domain").active_control_loss_stage = 1
	_check(actor.call("use_antidote"), "Emergency antidote is immediate")
	_check(not runtime.call("is_control_lost") and actor.get("antidotes") == stock - 2, "Emergency returns control and consumes one dose")
	actor.set("antidotes", 0)
	_check(not actor.call("use_antidote"), "No stock cannot spend an antidote")
	await _localization(runtime)
	actor.queue_free()
	actor.queue_free()
	await process_frame
	await process_frame
	print("Progression UI tests: %d failures" % failures)
	quit(failures)


func _localization(runtime: Node) -> void:
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/interface/translations.json"))
	for key: String in table.en:
		if key.begins_with("mutation") or key.begins_with("antidote") or key == "ampuleRecovered":
			_check(table.ru.has(key) and not str(table.ru[key]).is_empty(), "Russian localization key: " + key)
	for row in runtime.call("skill_catalog"):
		for suffix in ["_name", "_description"]:
			var key: String = "mutationSkill_" + str(row[0]) + suffix
			_check(table.en.has(key) and table.ru.has(key), "Both locales contain every skill: " + key)
	var tree := TREE_UI.new()
	root.add_child(tree)
	tree.configure(runtime)
	tree.open_tree()
	_check(_texts(tree).contains("Control threshold"), "English tree names the control threshold")
	LOCALIZATION.apply_language("ru")
	await process_frame
	_check(_texts(tree).contains("Порог контроля") and not _texts(tree).contains("STABILITY"), "Live language change updates header and tree")
	_check(TEXT.skill_name("muscle_memory") == "Мышечная память", "Skill names resolve Russian keys")
	LOCALIZATION.apply_language("en")
	await process_frame
	_check(_texts(tree).contains("Control threshold"), "Tree switches back to English")
	tree.close_tree()
	tree.queue_free()
	await process_frame


func _texts(node: Node) -> String:
	var result := ""
	for child in node.find_children("*", "Label", true, false):
		result += str(child.get("text")) + "\n"
	return result


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
