extends SceneTree
## Map mode setting (campaign / web) of the constructor: format and validation.

const MODE := preload("res://game/bootstrap/app/planning_map_mode.gd")
const VALIDATOR := preload("res://game/bootstrap/app/planning_layout_validator.gd")
var failures := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + what)


func _init() -> void:
	_check(MODE.current == "campaign" and not MODE.is_web(), "default mode is campaign")
	_check(MODE.valid("web") and MODE.valid("campaign"), "both modes are valid")
	_check(not MODE.valid("arena") and not MODE.valid(1) and not MODE.valid(null), "unknown values are rejected")
	_check(VALIDATOR.error({"objects": []}).is_empty(), "a map without the key (old map) is valid")
	_check(VALIDATOR.error({"objects": [], "map_mode_v1": "web"}).is_empty(), "web map is valid")
	_check(VALIDATOR.error({"objects": [], "map_mode_v1": 5}) == "invalid map_mode_v1", "bad mode is reported")
	MODE.restore(null, "web")
	_check(MODE.is_web() and MODE.capture(null) == "web", "restore web then capture")
	MODE.restore(null, "")
	_check(not MODE.is_web(), "a map without the key restores campaign")
	print("map mode tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)
