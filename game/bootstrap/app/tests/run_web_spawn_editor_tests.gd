extends SceneTree
## Web section of the spawn queue editor: hidden on campaign maps, edits land in config.web.

const EDITOR := preload("res://game/bootstrap/app/planning_spawn_queue_editor.gd")
const MODE := preload("res://game/bootstrap/app/planning_map_mode.gd")
var failures := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + what)


func _init() -> void:
	var editor: VBoxContainer = EDITOR.new()
	root.add_child(editor)
	editor.load_config({})
	_check(not editor.web_box.visible and not editor.config().has("web"), "campaign map: no web section, config untouched")
	MODE.restore(null, "web")
	editor.load_config({})
	_check(editor.web_box.visible and editor.config().has("web"), "web map: section shown")
	var grid_count_before: int = editor.web_box.get_child_count()
	editor.web_box.get_child(1).select(1)
	editor.web_box.get_child(1).item_selected.emit(1)
	_check(editor.config()["web"]["role"] == "boss", "role switches to boss")
	editor.web_box.get_child(1).select(0)
	editor.web_box.get_child(1).item_selected.emit(0)
	var add: Button = editor.web_box.get_child(editor.web_box.get_child_count() - 1)
	add.pressed.emit()
	_check(editor.config()["web"]["unlocks"].size() == 1, "a new kind is added")
	_check(editor.web_box.get_child_count() > grid_count_before, "its rows appear")
	MODE.restore(null, "")
	print("web spawn editor tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)
