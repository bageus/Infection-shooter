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


func _portals(zone: Node3D) -> int:
	return int((zone.overlay.mesh.material as ShaderMaterial).get_shader_parameter("portal_count"))


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
	await create_timer(0.6).timeout
	_expect(first.overlay.visible and second.overlay.visible and other.overlay.visible, "Closed rooms are dark")
	_expect(_portals(first) == 0, "A closed door gives no view")
	door.open = true
	await create_timer(0.6).timeout
	_expect(first.overlay.visible and second.overlay.visible, "An open door keeps the fog up")
	_expect(_portals(first) == 1 and _portals(second) == 0, "Only the room part by the door gets the opening")
	door.open = false
	await create_timer(0.6).timeout
	_expect(_portals(first) == 0, "Closing the door removes the opening")
	player.position = Vector3(4.5, 0.0, 0.5)
	await create_timer(0.6).timeout
	_expect(not first.overlay.visible and not second.overlay.visible, "Standing in one part lifts the fog of the whole room")
	_expect(other.overlay.visible, "Another room stays dark")
	player.position = Vector3(-3.0, 0.0, 0.5)
	await create_timer(0.6).timeout
	_expect(first.overlay.visible, "Leaving the room brings the fog back")
	player.position = Vector3(50.0, 0.0, 50.0)
	await create_timer(0.6).timeout
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
