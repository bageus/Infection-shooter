extends SceneTree
const PLAYER := preload("res://game/features/player/public/player.tscn")
const TREE_UI := preload("res://game/bootstrap/app/mutation_tree_ui.gd")
const CONFIRM := preload("res://game/bootstrap/app/antidote_confirmation.gd")
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
	var ui := CONFIRM.new()
	root.add_child(ui)
	ui.configure(actor)
	var stock: int = actor.get("antidotes")
	_check(not actor.call("use_antidote") and ui.is_open() and paused, "Ordinary skill loss opens a paused confirmation")
	_check(ui.dialog.dialog_text.contains("Muscle Memory") and ui.dialog.dialog_text.contains("30%") and ui.dialog.dialog_text.contains("20%"), "Preview names the lost skill and mutation change")
	_check(actor.get("antidotes") == stock and runtime.call("get_mutation") == 30.0, "Preview spends nothing")
	ui.call("_cancel")
	_check(not paused and actor.get("antidotes") == stock and runtime.call("skill_learned", "muscle_memory"), "Cancel preserves stock, skill and prior pause")
	paused = true
	actor.call("use_antidote")
	ui.call("_cancel")
	_check(paused, "Cancel preserves an already paused tree/menu context")
	paused = false
	actor.call("use_antidote")
	ui.call("_confirm")
	_check(not paused and actor.get("antidotes") == stock - 1 and runtime.call("get_mutation") == 20.0, "Confirm spends exactly one dose")
	_check(runtime.call("mutation_points") == 2 and not runtime.call("skill_learned", "muscle_memory"), "Spent skill point is refunded into retained budget")
	_check(not actor.call("confirm_antidote") and actor.get("antidotes") == stock - 1, "Confirmation cannot be replayed")
	# Stale confirmation rejects a changed skill/mutation state.
	runtime.get("_domain").mutation = 30.0
	runtime.call("upgrade_skill", "muscle_memory")
	actor.call("use_antidote")
	runtime.get("_domain").mutation = 29.0
	ui.call("_confirm")
	_check(actor.get("antidotes") == stock - 1 and runtime.call("get_mutation") == 29.0, "Changed state invalidates pending preview")
	# Emergency use with an active loss bypasses ordinary confirmation.
	runtime.get("_domain").mutation = 30.1
	runtime.get("_domain").control_loss_remaining = 2.0
	runtime.get("_domain").active_control_loss_stage = 1
	_check(actor.call("use_antidote") and not ui.is_open(), "Emergency antidote is immediate")
	_check(not runtime.call("is_control_lost") and actor.get("antidotes") == stock - 2, "Emergency returns control and consumes one dose")
	_check(not actor.call("use_antidote") and not ui.is_open(), "No stock cannot request or spend an antidote")
	await _localization(runtime, ui)
	ui.queue_free()
	actor.queue_free()
	await process_frame
	await process_frame
	print("Progression UI tests: %d failures" % failures)
	quit(failures)


func _localization(runtime: Node, confirmation: Node) -> void:
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
	tree.set("antidote_confirmation", confirmation)
	tree.open_tree()
	var actor: Node = runtime.get_parent()
	actor.set("antidotes", 1)
	runtime.get("_domain").mutation = 30.0
	runtime.call("upgrade_skill", "muscle_memory")
	actor.call("use_antidote")
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	tree.call("_input", escape)
	_check(tree.is_tree_open() and confirmation.call("is_open") and paused, "Escape cannot close the underlying tree or unpause an open confirmation")
	confirmation.call("_cancel")
	_check(paused and tree.is_tree_open(), "Cancel returns to the existing paused tree")
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
