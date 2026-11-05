extends SceneTree
const SCENE := "res://game/presentation/office_floor/public/structural/lab_glass_door.tscn"
const DOOR := preload("res://game/presentation/office_floor/interactive_door.gd")
const SFX := preload("res://game/core/audio/public/sound_events.gd")
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var player := Node3D.new()
	stage.add_child(player)
	player.position = Vector3(30, 0, 30)
	var door := (load(SCENE) as PackedScene).instantiate() as Node3D
	stage.add_child(door)
	await _settle()
	var controller := door.get_node_or_null("DoorController")
	_expect(controller != null and controller.get_script() == DOOR, "Scene has a DoorController")
	if controller == null:
		quit(1)
		return
	_expect(int(controller.mode) == 0, "Controller is a bidirectional swing door")
	_expect(controller.laboratory_sound, "Controller uses laboratory sounds")
	var pivot := door.find_child("DoorPivot", true, false)
	_expect(pivot != null, "Model has DoorPivot")
	for body in [door.get_node("Body")]:
		for shape: Node in body.find_children("*", "CollisionShape3D", true, false):
			_expect(pivot == null or not pivot.is_ancestor_of(shape), "No static collision under the moving leaf")
	_expect(not door.get_node("Body").find_children("*", "CollisionShape3D", true, false).is_empty(), "Static frame keeps its collision")
	_expect(_leaf_collision_is_static(door, pivot), "No static box covers the leaf")
	controller.configure_player(player)
	controller.request_open()
	var opened := false
	for i in 240:
		controller.request_open()
		await physics_frame
		if float(controller.get("_open_amount")) > 0.5:
			opened = true
			break
	_expect(opened, "request_open opens the door")
	_expect(_has_voice(door, "Sfx_laboratory_door_open"), "Open requests laboratory_door_open")
	var closed := false
	for i in 600:
		await physics_frame
		if float(controller.get("_open_amount")) == 0.0:
			closed = true
			break
	_expect(closed, "Door closes after the delay")
	_expect(_has_voice(door, "Sfx_laboratory_door_close"), "Close requests laboratory_door_close")
	_expect(SFX.has_event(&"laboratory_door_open") and SFX.has_event(&"laboratory_door_close"), "Catalog has laboratory events")
	stage.queue_free()
	print("Lab door tests: %d failure(s)." % failures)
	quit(failures)


func _has_voice(door: Node, voice: String) -> bool:
	return not door.find_children(voice, "", true, false).is_empty()


## True when no static collision box contains the leaf's centre.
func _leaf_collision_is_static(door: Node3D, pivot: Node) -> bool:
	var leaf := pivot.find_child("DoorLeaf", true, false) as MeshInstance3D if pivot != null else null
	if leaf == null:
		return false
	var center := leaf.global_transform * leaf.get_aabb().get_center()
	for shape: CollisionShape3D in door.find_children("*", "CollisionShape3D", true, false):
		var box := shape.shape as BoxShape3D
		if box == null or pivot.is_ancestor_of(shape):
			continue
		var local := shape.global_transform.affine_inverse() * center
		if absf(local.x) < box.size.x * 0.5 and absf(local.y) < box.size.y * 0.5 and absf(local.z) < box.size.z * 0.5:
			return false
	return true


func _settle() -> void:
	for i in 4:
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
