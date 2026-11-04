extends SceneTree
## A real door scene with a zone on each side: auto-detected rooms open when the door opens.
const DOOR := preload("res://game/presentation/office_floor/public/structural/only_door_2.tscn")
const ZONE := preload("res://game/presentation/office_floor/public/props/darkness_zone.tscn")
const DOOR_LINKS := preload("res://game/presentation/office_floor/public/door_darkness_links.gd")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _zone(z: float, room: int) -> Node3D:
	var zone := ZONE.instantiate() as Node3D
	zone.set("permanent", false)
	zone.set("room_id", room)
	zone.position = Vector3(0.0, 2.75, z)
	root.add_child(zone)
	return zone


func _run() -> void:
	var wall := DOOR.instantiate() as Node3D
	wall.position = Vector3.ZERO
	root.add_child(wall)
	var controller := wall.get_node("DoorController") as Node3D
	var front := _zone(2.5, 2)
	var back := _zone(-2.5, 5)
	await process_frame
	await process_frame
	var found: Array = DOOR_LINKS.detect(controller, controller)
	_expect(found == [2, 5], "Auto finds both rooms on either side of the door, got %s" % str(found))
	DOOR_LINKS.set_rooms(controller, found, true)
	await create_timer(0.1).timeout
	_expect(front.overlay.visible and back.overlay.visible, "Closed door keeps both rooms dark")
	controller.set("_open_amount", 1.0)
	await create_timer(0.6).timeout
	_expect(not front.overlay.visible, "Open door lifts the front room (list applied in game)")
	_expect(not back.overlay.visible, "Open door lifts the back room (list applied in game)")
	print("Door darkness flow tests: %d failure(s)." % failures)
	quit(failures)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAILED: " + label)
	print(("ok: " if condition else "FAIL: ") + label)
