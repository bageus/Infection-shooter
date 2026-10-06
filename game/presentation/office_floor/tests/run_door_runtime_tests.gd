extends SceneTree
const DOOR := preload("res://game/presentation/office_floor/interactive_door.gd")
const PRESENCE := preload("res://game/presentation/office_floor/door_presence.gd")
class Actor extends CharacterBody3D:
	var health := 100.0
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
