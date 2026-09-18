extends CanvasLayer

@onready var crosshair: Control = $Crosshair


func _process(_delta: float) -> void:
	crosshair.position = get_viewport().get_mouse_position()
