extends Control

const CHECKPOINT := preload("res://game/bootstrap/app/checkpoint_progress.gd")
const LEVEL_CHAIN := preload("res://game/bootstrap/app/level_chain.gd")

@onready var menu = $Menu
var _loading := false
var completion_music: Node


func _ready() -> void:
	get_window().title = "Infection Shooter"
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.action_requested.connect(_action)
	if is_instance_valid(completion_music):
		menu.get("_music").call("wait_for_completion", completion_music)


## Debug main menu: loads the chosen map and opens it in the planner once it is ready.
func _plan_map(path: String) -> void:
	_loading = true
	var loader := preload("res://game/bootstrap/app/menu/mission_loader.gd").new()
	add_child(loader)
	loader.completed.connect(func(_success: bool) -> void: _loading = false)
	loader.set("completion_music", completion_music)
	completion_music = null
	loader.set("open_planner", true)
	loader.start_map(path, path.get_file().get_basename(), {})


func _action(action: String) -> void:
	if _loading:
		return
	if action.begins_with("plan_map:"):
		_plan_map(action.trim_prefix("plan_map:"))
		return
	match action:
		"start", "restart":
			_loading = true
			var loader := preload("res://game/bootstrap/app/menu/mission_loader.gd").new()
			add_child(loader)
			loader.completed.connect(func(_success: bool) -> void: _loading = false)
			loader.set("completion_music", completion_music)
			completion_music = null
			# A level chain in the constructor starts a new game from its first map.
			var chain: RefCounted = LEVEL_CHAIN.new()
			chain.load_file()
			if chain.names().is_empty():
				loader.start()
			else:
				loader.start_map(CHECKPOINT.map_file(chain.names()[0]), chain.names()[0], {})
		"continue":
			var map_name := CHECKPOINT.resume_map()
			if map_name.is_empty():
				return
			_loading = true
			var loader := preload("res://game/bootstrap/app/menu/mission_loader.gd").new()
			add_child(loader)
			loader.completed.connect(func(_success: bool) -> void: _loading = false)
			loader.set("completion_music", completion_music)
			loader.set("checkpoint_notice", true)
			completion_music = null
			loader.start_map(CHECKPOINT.map_file(map_name), map_name, {})
		"quit":
			if OS.has_feature("web"):
				menu.reason_key = "webQuit"
				menu.refresh()
			else:
				get_tree().quit()
