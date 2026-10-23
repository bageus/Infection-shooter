extends SceneTree
## Exploration darkness rooms: shared door and presence, re-darkening, hero view and validator.
const ZONE := preload("res://game/presentation/office_floor/public/props/darkness_zone.tscn")
const LAYOUT_VALIDATOR := preload("res://game/bootstrap/app/planning_layout_validator.gd")
var failures := 0


class FakeDoor extends Node3D:
	var open := false
	func is_open_for_exploration() -> bool:
		return open


func _init() -> void:
	call_deferred("_run")


func _zone(x: float, room: int) -> Node3D:
	var zone := ZONE.instantiate() as Node3D
	zone.set("permanent", false)
	zone.set("room_id", room)
	zone.position = Vector3(x, 2.75, 0.0)
	root.add_child(zone)
	return zone


func _run() -> void:
	var player := Node3D.new()
	player.add_to_group("player")
	player.position = Vector3(50.0, 0.0, 50.0)
	root.add_child(player)
	var door := FakeDoor.new()
	door.add_to_group("interactive_doors")
	door.position = Vector3(-2.5, 0.0, 0.0)
	root.add_child(door)
	var first := _zone(0.0, 3)
	var second := _zone(4.0, 3)
	var other := _zone(20.0, 4)
	await process_frame
	await process_frame
	_expect(first.overlay.visible and second.overlay.visible and other.overlay.visible, "Closed rooms are dark")
	door.open = true
	await process_frame
	_expect(not first.overlay.visible and not second.overlay.visible, "An open door lights every part of its room")
	_expect(other.overlay.visible, "Another room stays dark")
	door.open = false
	await process_frame
	_expect(first.overlay.visible and second.overlay.visible, "Closing the door darkens the room again")
	player.position = Vector3(4.5, 0.0, 0.5)
	await process_frame
	_expect(not first.overlay.visible and not second.overlay.visible, "Standing in one part lights the whole room")
	player.position = Vector3(50.0, 0.0, 50.0)
	await process_frame
	_expect(first.blocks_view(Vector3(0.0, 8.0, 6.0), Vector3(0.0, 0.5, 0.0)), "Dark cover blocks the camera ray to the hero")
	_expect(not first.blocks_view(Vector3(0.0, 8.0, 6.0), Vector3(30.0, 0.5, 0.0)), "A ray outside the cover is not blocked")
	var bad := {"objects": [{"scene": "res://x.tscn", "room_id": "a"}]}
	_expect(LAYOUT_VALIDATOR.error(bad) != "", "Validator rejects a non-numeric room_id")
	print("Darkness room tests: %d failure(s)." % failures)
	quit(failures)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
