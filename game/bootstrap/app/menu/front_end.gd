extends Control

@onready var menu = $Menu


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.action_requested.connect(_action)


func _action(action: String) -> void:
	match action:
		"start", "restart":
			get_tree().change_scene_to_file("res://game/bootstrap/app/main.tscn")
		"quit":
			if OS.has_feature("web"):
				menu.reason_key = "webQuit"
				menu.refresh()
			else:
				get_tree().quit()
