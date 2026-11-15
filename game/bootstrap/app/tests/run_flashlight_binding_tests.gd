extends SceneTree
const BINDINGS := preload("res://game/bootstrap/app/menu/control_bindings.gd")
var failures := 0


func _initialize() -> void:
	var bindings := BINDINGS.new()
	_check("flashlight" in BINDINGS.ACTIONS and bindings.values["flashlight"] == {"kind": "key", "code": KEY_T}, "The flashlight has the T key in the controls menu")
	_check(bindings.bind("flashlight", _key(KEY_Z)) == "camera_left", "A key another action owns is refused")
	_check(bindings.bind("flashlight", _key(KEY_V)) == "" and bindings.values["flashlight"]["code"] == KEY_V, "The flashlight key can be rebound")
	var translations := JSON.parse_string(FileAccess.get_file_as_string("res://assets/interface/translations.json")) as Dictionary
	for language: String in translations:
		_check(not str((translations[language] as Dictionary).get("bind_flashlight", "")).is_empty(), "The flashlight row is named in " + language)
	print("Flashlight binding tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code as Key
	event.keycode = code as Key
	return event


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
