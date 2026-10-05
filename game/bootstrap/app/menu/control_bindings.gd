extends RefCounted
## Versioned keyboard/mouse preferences owned by bootstrap, never by gameplay.
const ACTIONS: Array[String] = ["move_up", "move_down", "move_left", "move_right", "sprint", "roll", "fire", "reload", "melee", "antidote", "pickup_weapon", "weapon_1", "weapon_2", "weapon_3", "weapon_4", "camera_left", "camera_right", "mutation_tree", "skill_1", "skill_2", "skill_3", "skill_4"]
const KEYS: Array[int] = [KEY_W, KEY_S, KEY_A, KEY_D, KEY_SHIFT, KEY_SPACE, 0, KEY_R, KEY_C, KEY_F, KEY_G, KEY_1, KEY_2, KEY_3, KEY_V, KEY_Q, KEY_E, KEY_M, KEY_4, KEY_5, KEY_6, KEY_7]
var values: Dictionary = {}


func _init() -> void:
	reset()


func reset() -> void:
	values.clear()
	for i in ACTIONS.size():
		values[ACTIONS[i]] = {"kind": "mouse", "code": MOUSE_BUTTON_LEFT} if ACTIONS[i] == "fire" else {"kind": "key", "code": KEYS[i]}


func load_config(config: ConfigFile) -> void:
	reset()
	# Process in authored order and reject malformed/conflicting saved bindings.
	var requested: Dictionary = {}
	for action in ACTIONS:
		var candidate: Variant = config.get_value("controls_v1", action, values[action])
		requested[action] = candidate if valid(candidate) else values[action]
	var seen: Dictionary = {}
	for action in ACTIONS:
		var signature := str(requested[action]["kind"]) + ":" + str(requested[action]["code"])
		if seen.has(signature):
			return # Atomic fallback to defaults, never leave an action unbound.
		seen[signature] = true
	values = requested


func save_config(config: ConfigFile) -> void:
	for action in ACTIONS:
		config.set_value("controls_v1", action, values[action])


func apply() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, event_for(values[action]))


func bind(action: String, event: InputEvent) -> String:
	if action not in ACTIONS:
		return "bindingUnsupported"
	var candidate := from_event(event)
	if not valid(candidate):
		return "bindingReserved"
	for other in ACTIONS:
		if other != action and values[other] == candidate:
			return other
	values[action] = candidate
	return ""


static func from_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if (event.ctrl_pressed and code != KEY_CTRL) or (event.alt_pressed and code != KEY_ALT) or (event.meta_pressed and code != KEY_META) or (event.shift_pressed and code != KEY_SHIFT):
			return {}
		return {"kind": "key", "code": code}
	if event is InputEventMouseButton:
		return {"kind": "mouse", "code": int(event.button_index)}
	return {}


static func valid(candidate: Variant) -> bool:
	if not candidate is Dictionary or not candidate.get("code") is int:
		return false
	var code := int(candidate["code"])
	if candidate.get("kind") == "mouse":
		return code in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]
	return candidate.get("kind") == "key" and code > 0 and code <= KEY_SPECIAL + 512 and code not in [KEY_ESCAPE, KEY_TAB, KEY_ENTER, KEY_KP_ENTER, KEY_UNKNOWN, KEY_F3]


static func event_for(config: Dictionary) -> InputEvent:
	if config["kind"] == "mouse":
		var event := InputEventMouseButton.new()
		event.button_index = int(config["code"]) as MouseButton
		return event
	var event := InputEventKey.new()
	event.physical_keycode = int(config["code"]) as Key
	return event


func label(action: String, language: String) -> String:
	var entry: Dictionary = values[action]
	if entry["kind"] == "mouse":
		return (["ЛКМ", "ПКМ", "СКМ"] if language == "ru" else ["LMB", "RMB", "MMB"])[int(entry["code"]) - 1]
	return OS.get_keycode_string(int(entry["code"]))
