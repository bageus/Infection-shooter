extends SceneTree

const MISSION_LAYOUT := preload("res://game/bootstrap/app/mission_layout.gd")
const KEY_HOLDER := preload("res://game/bootstrap/app/tests/fixtures/test_key_holder.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var layout: Node3D = MISSION_LAYOUT.new()
	root.add_child(layout)
	var player: Node3D = KEY_HOLDER.new()
	root.add_child(player)
	layout.set("_player", player)
	player.holding = true
	var near_door := _add_door(Vector3(5.0, 0.0, 0.0), true, false)
	_add_door(Vector3(-20.0, 0.0, 0.0), true, false)
	_add_door(Vector3(1.0, 0.0, 0.0), true, true)
	_add_door(Vector3(0.5, 0.0, 0.0), false, false)
	var target: Vector3 = layout.call("floor_hint_target")
	_check(target.is_equal_approx(near_door.global_position), "after pickup the nearest key-locked door is the goal, not a sealed or unlocked one")

	for door in get_nodes_in_group("test_doors"):
		door.queue_free()
	await process_frame
	layout.set("_openings", [Rect2(10.0, 10.0, 1.0, 1.0)] as Array[Rect2])
	target = layout.call("floor_hint_target")
	_check(target.is_equal_approx(Vector3(10.5, 0.0, 10.5)), "with no key door left, the goal falls back to the nearest exit")

	layout.free()
	player.free()
	print("Key door hint tests: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _add_door(at: Vector3, locked_by_key: bool, sealed: bool) -> Node3D:
	var door: Node3D = KEY_HOLDER.new()
	door.requires_emergency_key = locked_by_key
	door.permanently_locked = sealed
	door.add_to_group("interactive_doors")
	door.add_to_group("test_doors")
	root.add_child(door)
	door.global_position = at
	return door


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
