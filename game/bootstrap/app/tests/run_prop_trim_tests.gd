extends SceneTree
const TRIM := preload("res://game/bootstrap/app/planning_prop_trim.gd")
const QUALITY := preload("res://game/core/vfx/public/effects_quality.gd")
const ENV := "res://models/objects/enviroments/"
const MOUSE := ENV + "05/05_computer_mouse.glb"
const PHONE := ENV + "05/05_desk_phone.glb"
const CHAIR := ENV + "06/06_office_chair.glb"
var failures := 0


func _initialize() -> void:
	QUALITY.set_level(QUALITY.HIGH)
	_check(not TRIM.drops({}, MOUSE, false), "High keeps every model")
	QUALITY.set_level(QUALITY.MEDIUM)
	_check(TRIM.drops({}, MOUSE, false), "Medium drops a tiny model")
	_check(not TRIM.drops({}, PHONE, false), "Medium keeps a model over 0.25 m")
	QUALITY.set_level(QUALITY.LOW)
	_check(TRIM.drops({}, MOUSE, false), "Low drops a tiny model")
	_check(TRIM.drops({}, PHONE, false), "Low drops a small model")
	_check(not TRIM.drops({}, CHAIR, false), "Low keeps a large model")
	_check(not TRIM.drops({"scale_x": 6.0, "scale_y": 6.0, "scale_z": 6.0}, MOUSE, false), "A model scaled up past the limit stays")
	_check(not TRIM.drops({"object_id": "object_1"}, MOUSE, false), "A model with an object id stays")
	_check(not TRIM.drops({"desk_id": "desk_1"}, MOUSE, false), "A desk item stays")
	_check(not TRIM.drops({}, MOUSE, true), "The planner always shows everything")
	_check(not TRIM.drops({}, "res://game/features/pickups/public/medkit_pickup.tscn", false), "Pickups stay")
	_check(not TRIM.drops({}, ENV + "99/unknown_model.glb", false), "A model missing from the size table stays")
	QUALITY.set_level(QUALITY.HIGH)
	print("Prop trim tests: %d failure(s)" % failures)
	quit(failures)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
