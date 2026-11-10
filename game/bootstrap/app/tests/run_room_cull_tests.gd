extends SceneTree
## Room culling: furniture in a fully fogged room is hidden, comes back when the fog lifts, and structure,
## id-bound props and props outside the room stay drawn.
const ZONE := preload("res://game/presentation/office_floor/public/props/darkness_zone.tscn")
const ROOM_CULL := preload("res://game/presentation/office_floor/public/room_cull.gd")
const CHAIR := "res://models/objects/enviroments/06/06_conference_chair.glb"
const DOOR_LINKS := preload("res://game/presentation/office_floor/public/door_darkness_links.gd")
const WALL := "res://models/objects/enviroments/01/01_wall_straight.glb"
var failures := 0


class FakeDoor extends Node3D:
	var open := false
	func is_open_for_exploration() -> bool:
		return open


func _init() -> void:
	call_deferred("_run")


func _prop(x: float, path: String, record := {}) -> Node3D:
	var node := Node3D.new()
	node.position = Vector3(x, 0.0, 0.0)
	root.add_child(node)
	ROOM_CULL.tag(node, record, path)
	return node


func _run() -> void:
	var player := Node3D.new()
	player.add_to_group("player")
	player.position = Vector3(50.0, 0.0, 50.0)
	root.add_child(player)
	var door := FakeDoor.new()
	door.add_to_group("interactive_doors")
	DOOR_LINKS.set_rooms(door, [3])
	door.position = Vector3(-2.0, 0.0, 0.0)
	door.rotation.y = PI * 0.5
	root.add_child(door)
	var inside := _prop(0.0, CHAIR)
	var by_wall := _prop(1.9, CHAIR)
	var outside := _prop(8.0, CHAIR)
	var wall := _prop(0.0, WALL)
	var quest := _prop(0.5, CHAIR, {"object_id": "key"})
	var zone := ZONE.instantiate() as Node3D
	zone.set("permanent", false)
	zone.set("room_id", 3)
	zone.position = Vector3(0.0, 2.75, 0.0)
	root.add_child(zone)
	await create_timer(0.6).timeout
	_expect(not inside.visible, "Furniture in a fogged room is hidden")
	_expect(by_wall.visible and outside.visible, "Props at the wall and outside the room stay drawn")
	_expect(wall.visible and quest.visible, "Structure and id-bound props stay drawn")
	door.open = true
	await create_timer(0.4).timeout
	_expect(inside.visible, "Opening the door shows the furniture at once")
	door.open = false
	await create_timer(0.8).timeout
	_expect(not inside.visible, "Closing the door hides it again")
	player.position = Vector3(0.0, 0.0, 0.0)
	await create_timer(0.2).timeout
	_expect(inside.visible, "Entering the room shows the furniture")
	player.position = Vector3(50.0, 0.0, 50.0)
	await create_timer(0.8).timeout
	_expect(not inside.visible, "Fogged again before the quality check")
	inside.set_meta(&"trim_hidden", true)
	player.position = Vector3(0.0, 0.0, 0.0)
	await create_timer(0.2).timeout
	_expect(not inside.visible, "Entering the room does not show a prop the quality setting hides")
	inside.set_meta(&"trim_hidden", false)
	inside.visible = true
	Engine.set_meta("planning_active", true)
	player.position = Vector3(50.0, 0.0, 50.0)
	await create_timer(0.8).timeout
	_expect(inside.visible, "The open planner always shows the furniture")
	Engine.set_meta("planning_active", false)
	print("Room cull tests: %d failure(s)." % failures)
	quit(failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
