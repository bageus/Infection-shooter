extends SceneTree
const DOOR := preload("res://game/presentation/office_floor/interactive_door.gd")
const DOORS := 200

class Player extends Node3D:
	var key := false
	var key_queries := 0
	func has_emergency_key() -> bool:
		key_queries += 1
		return key

class CountedDoor extends "res://game/presentation/office_floor/interactive_door.gd":
	var glass_checks := 0
	func _refresh_glass_collision() -> void:
		glass_checks += 1
		super._refresh_glass_collision()

class Glass extends StaticBody3D:
	var _broken := false

var failures := 0
var stage: Node3D
var player: Player


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	player = Player.new()
	stage.add_child(player)
	_far_cost()
	_responsiveness()
	_custom_trigger()
	await _glass_coordinates_and_collision()
	stage.free()
	await process_frame
	print("Door idle tests: %d failure(s)." % failures)
	quit(0 if failures == 0 else 1)


func _door(at: Vector3, mode: int = DOOR.DoorMode.SWING_BIDIRECTIONAL) -> Node3D:
	var frame := Node3D.new()
	frame.position = at
	stage.add_child(frame)
	var door := CountedDoor.new()
	door.mode = mode
	door.configure_player(player)
	frame.add_child(door)
	door.set_physics_process(false)
	return door


func _far_cost() -> void:
	player.position = Vector3(0, 0, 100)
	var doors: Array = []
	for index in DOORS:
		var door := _door(Vector3(index * 4, 0, 0))
		door.configure_lock_state(DOOR.LOCK_KEY)
		door.call("_physics_process", 1.0 / 60.0)
		door.set("glass_checks", 0)
		doors.append(door)
	player.key_queries = 0
	var started := Time.get_ticks_usec()
	for tick in 60:
		for door: Node3D in doors:
			door.call("_physics_process", 1.0 / 60.0)
	var elapsed := Time.get_ticks_usec() - started
	var glass_checks := 0
	for door: Node3D in doors:
		glass_checks += int(door.get("glass_checks"))
		_expect(door.get("_open_amount") == 0.0, "Distant locked door stays closed")
		_expect(not (door.get("_key_hint") as Node3D).visible, "Distant lock badge remains hidden")
	_expect(player.key_queries == 0, "Closed distant doors do not ask for the emergency key (%d queries)" % player.key_queries)
	_expect(glass_checks == 0, "Ordinary doors do not run glass collision checks (%d)" % glass_checks)
	print("DOOR_IDLE_METRICS doors=%d ticks=60 key_queries=%d glass_checks=%d callback_usec=%d" % [DOORS, player.key_queries, glass_checks, elapsed])
	for door: Node3D in doors:
		door.get_parent().free()


func _responsiveness() -> void:
	player.key = false
	for mode in DOOR.DoorMode.values():
		player.position = Vector3(100, 0, 100)
		var door := _door(Vector3.ZERO, mode)
		door.call("_physics_process", 0.1)
		player.position = door.to_global(Vector3(0, 0, 0.5))
		door.call("_physics_process", 0.1)
		_expect(is_equal_approx(float(door.get("_open_amount")), 0.165), "Approach/teleport opens on the first tick (mode %d)" % mode)
		player.position = Vector3(100, 0, 100)
		for tick in 18: door.call("_physics_process", 0.1)
		_expect(door.get("_open_amount") == 0.0, "Door finishes its delay and closes while player is far (mode %d)" % mode)
		if mode == DOOR.DoorMode.SLIDING_ELEVATOR:
			door.call("request_open")
			door.call("_physics_process", 0.1)
			_expect(float(door.get("_open_amount")) > 0.0, "Remote elevator request bypasses idle guard immediately")
		door.get_parent().free()
	var keyed := _door(Vector3.ZERO)
	keyed.configure_lock_state(DOOR.LOCK_KEY)
	player.position = Vector3(0, 0, -0.5)
	keyed.call("_physics_process", 0.1)
	_expect(keyed.get("_open_amount") == 0.0 and not keyed.get("_locked_cue_armed"), "Keyless approach is blocked and arms one cue")
	player.key = true
	keyed.call("_physics_process", 0.1)
	_expect(float(keyed.get("_open_amount")) > 0.0, "Key gained without moving opens immediately")
	player.position = Vector3(100, 0, 100)
	for tick in 20: keyed.call("_physics_process", 0.1)
	_expect(keyed.get("_locked_cue_armed"), "Walking away re-arms locked cue")
	keyed.configure_lock_state(DOOR.LOCK_SEALED)
	player.position = Vector3(0, 0, 0.5)
	keyed.call("_physics_process", 0.1)
	_expect(keyed.get("_open_amount") == 0.0, "Sealed door remains blocked with key and from exit side")
	keyed.configure_lock_state(DOOR.LOCK_OPEN)
	keyed.call("_physics_process", 0.1)
	_expect(float(keyed.get("_open_amount")) > 0.0, "Planner unlock takes effect on the next physics tick")
	keyed.get_parent().free()
	var moved := _door(Vector3(10, 0, 20))
	player.position = Vector3(100, 0, 100)
	moved.call("_physics_process", 0.1)
	var parent := moved.get_parent() as Node3D
	parent.rotation = Vector3(0.1, 1.1, 0.2)
	parent.scale = Vector3(2, 1, 0.5)
	parent.position += Vector3(3, 2, -1)
	# The existing trigger uses local XZ, even when local Y is far above the door.
	player.position = moved.to_global(Vector3(0, 7, 0.5))
	moved.call("_physics_process", 0.1)
	_expect(float(moved.get("_open_amount")) > 0.0, "Live parent rotation/scale/translation and local-plane distance are respected")
	parent.free()


func _custom_trigger() -> void:
	var door := _door(Vector3.ZERO)
	door.trigger_distance = 8.0
	player.position = Vector3(100, 0, 100)
	door.call("_physics_process", 0.1)
	player.position = Vector3(0, 0, 7.0)
	door.call("_physics_process", 0.1)
	_expect(float(door.get("_open_amount")) > 0.0, "Authored trigger larger than the idle radius opens immediately")
	door.get_parent().free()
	door = _door(Vector3.ZERO, DOOR.DoorMode.SWING_ONE_WAY)
	player.position = Vector3(0, 0, -0.5)
	door.call("_physics_process", 0.1)
	_expect(door.get("_open_amount") == 0.0, "One-way door does not open from the forbidden side")
	door.get_parent().free()


func _glass_coordinates_and_collision() -> void:
	var frame := Node3D.new()
	stage.add_child(frame)
	var visual := Node3D.new()
	visual.name = "Visual"
	visual.position.x = 15
	frame.add_child(visual)
	var leaf := MeshInstance3D.new()
	leaf.name = "DoorGlass"
	leaf.mesh = BoxMesh.new()
	visual.add_child(leaf)
	var glass := Glass.new()
	glass.name = "GlassBody"
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	glass.add_child(shape)
	frame.add_child(glass)
	var door := DOOR.new()
	door.mode = DOOR.DoorMode.GLASS_SWING
	door.configure_player(player)
	frame.add_child(door)
	door.set_physics_process(false)
	player.position = Vector3(0, 0, 0.5)
	door.call("_physics_process", 0.1)
	_expect(door.get("_open_amount") == 0.0, "Shifted glass visual, rather than controller origin, defines proximity")
	player.position = Vector3(0, 0, -5)
	door.call("_physics_process", 0.1)
	_expect(float(door.get("_swing_side")) < 0.0, "Walking around a distant glass door updates its opening side")
	visual.position.x += 5
	player.position = visual.global_position + Vector3(0, 0, 0.5)
	door.call("_physics_process", 0.1)
	_expect(float(door.get("_open_amount")) > 0.0, "Moving glass Visual updates proximity without a stale cache")
	# Defensive collider repair must still work far from the player.
	player.position = Vector3(100, 0, 100)
	door.set("_open_amount", 0.0)
	door.set("_close_timer", 0.0)
	glass._broken = true
	door.call("_physics_process", 0.1)
	await process_frame
	_expect(shape.disabled, "Broken glass collision remains disabled even on an idle door")
	shape.disabled = false
	door.call("_physics_process", 0.1)
	await process_frame
	_expect(shape.disabled, "External reactivation cannot restore broken pane collision")
	frame.remove_child(door)
	frame.add_child(door)
	shape.disabled = false
	door.call("_physics_process", 0.1)
	await process_frame
	_expect(shape.disabled, "Tree reentry reconnects glass bindings and restores broken collision")
	var late := CollisionShape3D.new()
	late.shape = BoxShape3D.new()
	glass.add_child(late)
	door.call("_physics_process", 0.1)
	await process_frame
	_expect(late.disabled, "Late collider is included in broken glass repair")
	late.free()
	shape.free()
	door.call("_physics_process", 0.1)
	glass.free()
	door.call("_physics_process", 0.1)
	frame.free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
