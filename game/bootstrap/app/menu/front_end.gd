extends Control

@onready var menu = $Menu
var _loading := false


func _ready() -> void:
	get_window().title = "Infection Shooter"
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.action_requested.connect(_action)


func _action(action: String) -> void:
	if _loading:
		return
	match action:
		"start", "restart":
			_loading = true
			var loader := preload("res://game/bootstrap/app/menu/mission_loader.gd").new()
			add_child(loader)
			loader.completed.connect(func(_success: bool) -> void: _loading = false)
			loader.start()
		"quit":
			if OS.has_feature("web"):
				menu.reason_key = "webQuit"
				menu.refresh()
			else:
				get_tree().quit()
