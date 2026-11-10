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
	var boxes := ENV + "04/04_cardboard_box_open.glb"
	_check(TRIM.drops({"scale_x": 1.5, "scale_y": 1.5, "scale_z": 1.5}, boxes, false), "Low drops cardboard boxes at any scale")
	QUALITY.set_level(QUALITY.MEDIUM)
	_check(not TRIM.drops({}, boxes, false), "Medium keeps cardboard boxes")
	QUALITY.set_level(QUALITY.LOW)
	_check(not TRIM.drops({"scale_x": 6.0, "scale_y": 6.0, "scale_z": 6.0}, MOUSE, false), "A model scaled up past the limit stays")
	_check(not TRIM.drops({"object_id": "object_1"}, MOUSE, false), "A model with an object id stays")
	_check(not TRIM.drops({"desk_id": "desk_1"}, MOUSE, false), "A desk item stays")
	_check(not TRIM.drops({}, MOUSE, true), "The planner always shows everything")
	_check(not TRIM.drops({}, "res://game/features/pickups/public/medkit_pickup.tscn", false), "Pickups stay")
	_check(not TRIM.drops({}, ENV + "99/unknown_model.glb", false), "A model missing from the size table stays")
	var node := Node3D.new()
	root.add_child(node)
	var body := StaticBody3D.new()
	body.collision_layer = 5
	node.add_child(body)
	await process_frame
	TRIM.tag(node, {}, MOUSE)
	_check(not node.visible, "Low hides tagged tiny decor on tagging")
	_check(node.process_mode == Node.PROCESS_MODE_DISABLED and body.collision_layer == 0, "Hidden decor stops processing and hits")
	QUALITY.set_level(QUALITY.HIGH)
	TRIM.apply_live(self)
	_check(node.visible, "High shows tagged decor again at once")
	_check(node.process_mode == Node.PROCESS_MODE_INHERIT and body.collision_layer == 5, "Shown decor gets its processing and hits back")
	QUALITY.set_level(QUALITY.MEDIUM)
	TRIM.apply_live(self)
	_check(not node.visible, "Medium hides it again at once")
	QUALITY.set_level(QUALITY.HIGH)
	node.set_meta(&"room_culled", true)
	TRIM.apply_live(self)
	_check(not node.visible, "A quality change does not show decor its room still hides")
	node.set_meta(&"room_culled", false)
	TRIM.apply_live(self)
	QUALITY.set_level(QUALITY.MEDIUM)
	TRIM.apply_live(self)
	Engine.set_meta("planning_active", true)
	TRIM.apply_live(self)
	_check(node.visible, "The open planner shows trimmed decor")
	Engine.set_meta("planning_active", false)
	TRIM.apply_live(self)
	_check(not node.visible, "Leaving the planner trims it again")
	node.free()
	QUALITY.set_level(QUALITY.HIGH)
	print("Prop trim tests: %d failure(s)" % failures)
	quit(failures)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
