extends Label

var _elapsed := 0.0

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.25:
		return
	_elapsed = 0.0
	var enemies := get_tree().get_nodes_in_group("infected").size()
	text = "FPS %d  |  ENEMIES %d" % [Engine.get_frames_per_second(), enemies]
