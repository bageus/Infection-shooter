extends RefCounted
## Input labels and animated key-cap layouts for lessons.


## Short label of the first event bound to an action ("W", "SPACE", "LMB").
static func binding(action: String) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "?"
	var event: InputEvent = events[0]
	if event is InputEventMouseButton:
		return ["LMB", "RMB", "MMB"][clampi(event.button_index - 1, 0, 2)]
	if event is InputEventKey:
		return OS.get_keycode_string(event.physical_keycode if event.physical_keycode else event.keycode)
	return event.as_text()


## Movement cross: forward, back, left, right (the order they light up).
static func movement() -> Array:
	return [
		{"text": binding("move_up"), "x": 1.0, "y": 0.0},
		{"text": binding("move_down"), "x": 1.0, "y": 1.0},
		{"text": binding("move_left"), "x": 0.0, "y": 1.0},
		{"text": binding("move_right"), "x": 2.0, "y": 1.0},
	]


## One row of keys for the given actions.
static func row(actions: Array) -> Array:
	var layout := []
	var x := 0.0
	for action: String in actions:
		var text := binding(action)
		var width := 1.0 if text.length() <= 2 else 2.0
		layout.append({"text": text, "x": x, "y": 0.0, "w": width})
		x += width
	return layout
