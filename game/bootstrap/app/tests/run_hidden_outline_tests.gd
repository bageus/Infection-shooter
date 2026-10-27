extends SceneTree
## Items behind a wall get a yellow rim only when close and in the player's room.
const EFFECTS := preload("res://game/bootstrap/app/occlusion_effects.gd")
const ROOM_STUB := """
extends Node3D
var room_id := 0
var permanent := false
var rect := Rect2()
var fog := false
func blocks_view(_from: Vector3, _to: Vector3) -> bool:
	return fog
func _edge_distance(point: Vector3) -> float:
	return 0.0 if rect.has_point(Vector2(point.x, point.z)) else 5.0
"""
var scene: Node3D
var camera: Camera3D
var hero: Node3D
var wall: Node3D
var item: Node3D
var effects: Node
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.msaa_3d = Viewport.MSAA_DISABLED
	_make_fixture()
	await _settle()
	_check(_shown(), "hidden crate near the hero in open space is outlined")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		_capture(image, "outline")
		var centre := _pixel(image, camera.unproject_position(item.global_position + Vector3.UP * 0.5))
		_check(not _is_yellow(centre), "outline leaves the item interior clear")
		_check(_yellow_count(image, camera.unproject_position(item.global_position + Vector3.UP * 0.5)) > 20, "rim pixels are yellow")
	item.position.x = 8.0
	await _settle()
	_check(not _shown(), "beyond 6 m nothing is outlined")
	item.position.x = 1.5
	var divider := _box_wall(Vector3(0.75, 1, 0), Vector3(0.2, 6, 2))
	await _settle()
	_check(not _shown(), "a wall between hero and item means another room")
	divider.free()
	await _settle()
	_check(_shown(), "outline returns once the wall is gone")
	wall.scene_file_path = "res://game/presentation/office_floor/public/structural/glass_wall_full.tscn"
	await _settle()
	_check(not _shown(), "a glass wall does not hide an item from the camera")
	wall.scene_file_path = ""
	var room_a := _room(1, Rect2(-1, -2, 1.5, 4))
	var room_b := _room(2, Rect2(0.8, -2, 4, 4))
	await _settle()
	_check(not _shown(), "different fog-of-war rooms never outline")
	room_b.rect = Rect2(0.8, -2, 4, 4)
	room_b.room_id = 1
	await _settle()
	_check(_shown(), "same fog-of-war room outlines")
	room_b.rect = Rect2(5, -2, 1, 4)
	room_b.room_id = 0
	await _settle()
	_check(not _shown(), "hero in a room never outlines items outside it, even with a doorway between")
	room_b.rect = Rect2(0.8, -2, 4, 4)
	room_b.room_id = 1
	room_b.fog = true
	wall.position.x = 20.0
	await _settle()
	_check(_shown(), "an item under solid fog counts as hidden")
	room_b.fog = false
	wall.position.x = 0.0
	room_a.free()
	room_b.free()
	wall.position.x = 20.0
	await _settle()
	_check(not _shown(), "a visible item is not outlined")
	wall.position.x = 0.0
	item.remove_from_group("hidden_outline")
	item.add_to_group("occlusion_items")
	item.set("scene_file_path", "res://game/features/pickups/public/dna_pickup.tscn")
	await _settle()
	_check(not _shown(), "DNA is not on the outlined list")
	wall.position.x = 0.0
	await _door_check()
	print("Hidden outline tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _door_check() -> void:
	var door_root := Node3D.new()
	scene.add_child(door_root)
	door_root.position = Vector3(-1.5, 0, 0)
	var visual := Node3D.new()
	visual.name = "Visual"
	door_root.add_child(visual)
	_mesh(visual, Vector3(0, 1, 0), Vector3(1, 2, 0.1), Color(0.3, 0.3, 0.9))
	var controller := Node3D.new()
	controller.set_script(load("res://game/bootstrap/app/tests/fixtures/door_stub.gd"))
	controller.add_to_group("interactive_doors")
	door_root.add_child(controller)
	await _settle()
	var outline = effects.outlines.outlines.get(controller.get_instance_id())
	_check(outline != null and outline.shown and not outline.copies.is_empty(), "a hidden door gets its leaf outlined")
	var rooms := [_room(3, Rect2(-4, -2, 6, 2.3)), _room(4, Rect2(-4, 0.3, 6, 1.2)), _room(5, Rect2(-4, 1.5, 6, 1.4))]
	await _settle()
	_check(effects.outlines.outlines[controller.get_instance_id()].shown, "a door between two rooms outlines from either side")
	hero.position.z = 2.0
	await _settle()
	_check(not effects.outlines.outlines[controller.get_instance_id()].shown, "a door in neither of the hero's rooms stays plain")
	hero.position.z = 0.0
	for room in rooms:
		room.free()


func _shown() -> bool:
	var outline = effects.outlines.outlines.get(item.get_instance_id())
	return outline != null and outline.shown


func _make_fixture() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.08, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env_node.environment = env
	scene.add_child(env_node)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0, 5, 8)
	camera.look_at(Vector3(0, 1, 0))
	camera.current = true
	hero = Node3D.new()
	hero.add_to_group("player")
	scene.add_child(hero)
	_mesh(hero, Vector3(0, 0.8, 0), Vector3(0.7, 1.6, 0.5), Color(0.15, 0.9, 0.1))
	wall = _box_wall(Vector3(0, 1, 3), Vector3(7, 6, 0.3))
	item = Node3D.new()
	item.add_to_group("hidden_outline")
	scene.add_child(item)
	item.position = Vector3(1.5, 0, 0)
	_mesh(item, Vector3(0, 0.5, 0), Vector3.ONE, Color(0.9, 0.1, 0.1))
	effects = EFFECTS.new()
	scene.add_child(effects)
	effects.setup(hero, camera, scene)


func _room(id: int, rect: Rect2) -> Node3D:
	var script := GDScript.new()
	script.source_code = ROOM_STUB
	script.reload()
	var zone := Node3D.new()
	zone.set_script(script)
	zone.room_id = id
	zone.rect = rect
	zone.add_to_group("darkness_zone")
	scene.add_child(zone)
	return zone


func _box_wall(at: Vector3, size: Vector3) -> Node3D:
	var node := Node3D.new()
	node.add_to_group("camera_occluder")
	scene.add_child(node)
	node.position = at
	_mesh(node, Vector3.ZERO, size, Color(0.32, 0.32, 0.32))
	var body := StaticBody3D.new()
	node.add_child(body)
	var shape := CollisionShape3D.new()
	var bounds := BoxShape3D.new()
	bounds.size = size
	shape.shape = bounds
	body.add_child(shape)
	return node


func _mesh(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	parent.add_child(mesh)
	mesh.position = at
	return mesh


func _settle() -> void:
	for _i in 12:
		await physics_frame
	await process_frame


func _pixel(image: Image, point: Vector2) -> Color:
	var scale := Vector2(image.get_size()) / get_root().get_visible_rect().size
	return image.get_pixelv(Vector2i(point * scale))


func _is_yellow(color: Color) -> bool:
	return color.r > 0.8 and color.g > 0.6 and color.b < 0.4


func _yellow_count(image: Image, around: Vector2) -> int:
	var count := 0
	var scale := Vector2(image.get_size()) / get_root().get_visible_rect().size
	for x in range(-120, 120):
		for y in range(-120, 120):
			var p := Vector2i(around * scale) + Vector2i(x, y)
			if image.get_size().x > p.x and p.x >= 0 and image.get_size().y > p.y and p.y >= 0 and _is_yellow(image.get_pixelv(p)):
				count += 1
	return count


func _capture(image: Image, name: String) -> void:
	var dir := OS.get_environment("OUTLINE_CAPTURE_DIR")
	if not dir.is_empty():
		image.save_png("%s/%s.png" % [dir, name])


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
