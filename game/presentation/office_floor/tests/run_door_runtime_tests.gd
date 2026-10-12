extends SceneTree
const DOOR := preload("res://game/presentation/office_floor/interactive_door.gd")
const PRESENCE := preload("res://game/presentation/office_floor/door_presence.gd")
class Actor extends CharacterBody3D:
	var health := 100.0

## Player holding the emergency key.
class KeyHolder extends Node3D:
	func has_emergency_key() -> bool:
		return true
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var frame := Node3D.new()
	stage.add_child(frame)
	frame.position = Vector3(5, 0, 7)
	frame.rotation.y = .8
	frame.scale = Vector3(1.3, 1, 1.3)
	var presence := PRESENCE.new()
	frame.add_child(presence)
	var actor := Actor.new()
	actor.add_to_group("infected")
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	actor.add_child(shape)
	stage.add_child(actor)
	actor.global_position = frame.to_global(Vector3(0, .5, 0))
	await _settle()
	_expect(presence.occupied(frame), "Nearby live infected holds emergency door")
	actor.health = 0
	_expect(not presence.occupied(frame), "Dead actor does not hold door")
	actor.health = 100
	actor.global_position = frame.to_global(Vector3(1.2, .5, 0))
	await _settle()
	_expect(not presence.occupied(frame), "Overlapping capsule outside original origin bounds does not hold door")
	actor.global_position = frame.to_global(Vector3(0, .5, 0))
	await _settle()
	actor.queue_free()
	await _settle()
	_expect(not presence.occupied(frame), "Actor deletion releases presence")
	await _test_elevators(stage)
	await _test_lock_states(stage)
	stage.queue_free()
	await _settle()
	print("Door runtime tests: %d failure(s)." % failures)
	quit(failures)

func _test_elevators(stage: Node3D) -> void:
	var player := Node3D.new()
	stage.add_child(player)
	player.position = Vector3(40, 0, 40)
	var a := _door(stage, player, Vector3.ZERO)
	var b := _door(stage, player, Vector3(2, 0, 0))
	await _settle()
	a.call("_request_nearby_elevator_open")
	_expect(b.get("_requested_open"), "Bound adjacent elevator receives request")
	b.set("_requested_open", false)
	b.position.x = 9
	a.call("_request_nearby_elevator_open")
	_expect(not b.get("_requested_open"), "Moved neighbor uses live distance")
	var c := _door(stage, player, Vector3(1, 0, 0))
	await _settle()
	a.call("_request_nearby_elevator_open")
	_expect(c.get("_requested_open"), "Runtime addition binds reciprocally")
	c.queue_free()
	await _settle()
	a.call("_request_nearby_elevator_open")
	stage.remove_child(b)
	a.call("_request_nearby_elevator_open")
	stage.add_child(b)
	b.position.x = 2
	await _settle()
	b.set("_requested_open", false)
	a.call("_request_nearby_elevator_open")
	_expect(b.get("_requested_open"), "Tree reentry restores elevator binding")
	_test_pose(a)

func _test_lock_states(stage: Node3D) -> void:
	var player := Node3D.new()
	stage.add_child(player)
	player.position = Vector3(60, 0, 60)
	# Key door configured before it enters the tree (planner restore path).
	var keyed := DOOR.new()
	keyed.configure_lock_state(DOOR.LOCK_KEY)
	keyed.configure_player(player)
	keyed.set_physics_process(false)
	keyed.position = Vector3(80, 0, 0)
	stage.add_child(keyed)
	await _settle()
	_expect(keyed.get_lock_state() == DOOR.LOCK_KEY, "Key lock state survives configuration before entering the tree")
	_expect(keyed.get_node_or_null("LockedDoorIcon") != null, "Key-locked door gets its locked icon")
	_expect(keyed.get_node("LockedDoorIcon").scale.is_equal_approx(Vector3.ONE * DOOR.LOCK_ICON_SCALE), "Locked icon is 20 percent smaller")
	_expect(is_equal_approx(keyed.get_node("LockedDoorIcon").position.y, DOOR.LOCK_ICON_HEIGHT), "Locked icon sits at door-centre height")
	# Standing in front of a locked door (not on its exit side): one cue per approach.
	player.position = keyed.to_global(Vector3(0, 0, -0.5))
	keyed.call("_physics_process", .016)
	keyed.call("_physics_process", .016)
	_expect(keyed.get("_open_amount") == 0.0, "Key door stays shut without the key")
	_expect(keyed.get("_locked_cue_armed") == false, "Locked cue plays once per approach")
	player.position = keyed.to_global(Vector3(0, 0, -3.0))
	keyed.call("_physics_process", .016)
	_expect(keyed.get("_locked_cue_armed") == true, "Locked cue re-arms after walking away")
	# Key holder opens the key door.
	var holder := KeyHolder.new()
	stage.add_child(holder)
	keyed.configure_player(holder)
	holder.position = keyed.to_global(Vector3(0, 0, -0.5))
	keyed.call("_physics_process", .016)
	keyed.call("_physics_process", .016)
	_expect(keyed.get("_open_amount") > 0.0, "Key holder opens a key-locked door")
	keyed.set("_open_amount", 0.0)
	# Sealed doors never open, not for the key holder and not from the exit side.
	var sealed := DOOR.new()
	sealed.configure_lock_state(DOOR.LOCK_SEALED)
	sealed.configure_player(holder)
	sealed.set_physics_process(false)
	sealed.position = Vector3(84, 0, 0)
	stage.add_child(sealed)
	await _settle()
	_expect(sealed.get_lock_state() == DOOR.LOCK_SEALED, "Sealed lock state is reported back")
	_expect(sealed.get("requires_emergency_key") and sealed.get("permanently_locked"), "Sealed door is key-locked and permanently locked")
	for z in [-0.5, 0.5]:
		holder.position = sealed.to_global(Vector3(0, 0, z))
		sealed.call("_physics_process", .016)
		sealed.call("_physics_process", .016)
	_expect(sealed.get("_open_amount") == 0.0, "Sealed door never opens")
	# Planner switches a live door back to open: it swings again.
	var plain := DOOR.new()
	plain.configure_lock_state(DOOR.LOCK_OPEN)
	plain.configure_player(player)
	plain.set_physics_process(false)
	stage.add_child(plain)
	await _settle()
	_expect(plain.get_node_or_null("LockedDoorIcon") == null, "Open door has no locked icon")
	plain.configure_lock_state(DOOR.LOCK_KEY)
	_expect(plain.get_node("LockedDoorIcon").visible, "Locking a live door shows its icon")
	plain.configure_lock_state(DOOR.LOCK_OPEN)
	_expect(not plain.get_node("LockedDoorIcon").visible, "Unlocking a live door hides its icon")
	player.position = plain.to_global(Vector3(0, 0, -0.5))
	plain.call("_physics_process", .016)
	_expect(plain.get("_open_amount") > 0.0, "Open door swings for the player")
	var elevator := DOOR.new()
	elevator.mode = DOOR.DoorMode.SLIDING_ELEVATOR
	_expect(not elevator.is_lockable(), "Elevator doors are not lockable")
	elevator.free()
	plain.queue_free()
	keyed.queue_free()
	sealed.queue_free()
	await _settle()

func _test_pose(a: Node3D) -> void:
	var part := Node3D.new()
	a.add_child(part)
	a.get("_door_parts").append(part)
	a.get("_closed_transforms").append(Transform3D.IDENTITY)
	a.set("_open_amount", 0.0)
	a.set("_pose_ready", false)
	a.call("_physics_process", .016)
	part.position.y = .25
	a.call("_physics_process", .016)
	_expect(part.position.y == .25, "Closed stationary door does not rewrite leaf transform")
	a.call("request_open")
	a.call("_physics_process", .016)
	_expect(a.get("_open_amount") > 0 and part.position.y == 0, "Moving door writes current pose")

func _door(stage: Node3D, player: Node3D, at: Vector3) -> Node3D:
	var door := DOOR.new()
	door.mode = DOOR.DoorMode.SLIDING_ELEVATOR
	door.configure_player(player)
	stage.add_child(door)
	door.position = at
	door.set_physics_process(false)
	return door

func _settle() -> void:
	for i in 3:
		await physics_frame

func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
