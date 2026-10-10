extends SceneTree
const SNAP := preload("res://game/bootstrap/app/planning_edge_snap.gd")
const FLOOR := preload("res://game/bootstrap/app/floor_wall_snap.gd")
const GEOMETRY := preload("res://game/bootstrap/app/planning_geometry.gd")
const CATALOG := preload("res://game/bootstrap/app/planning_catalog.gd")
var failures := 0
var stage: Node3D

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	_test_edges()
	_test_walls()
	await _test_floor_walls()
	_test_cabinets()
	await _capture_contacts()
	stage.queue_free()
	await process_frame
	print("Planner contacts: %d failures" % failures)
	quit(failures)

func _node(position: Vector3, angle: float = 0.0, wall: bool = false) -> Node3D:
	var node := Node3D.new()
	stage.add_child(node)
	node.position = position
	node.rotation.y = angle
	if wall:
		node.set_meta("planning_scene_path", "wall_straight.tscn")
	return node

func _test_edges() -> void:
	var box := AABB(Vector3(1.0, 0, -.3), Vector3(2.0, 2, .6))
	for angle in [0.0, PI / 2, PI / 4]:
		var target := _node(Vector3(0, 0, 0), angle)
		var source := _node(target.basis.x * 2.2, angle)
		source.scale = Vector3(1.5, 1, 1)
		var proposed := target.basis.x * 1.65 # offset pivot + different widths/scales
		var result := SNAP.position_for(source, box, proposed, [{"node": target, "bounds": box}])
		var a := Transform3D(source.global_basis, result) * Vector3(box.position.x, 0, box.position.z)
		var b := target.global_transform * Vector3(box.end.x, 0, box.position.z)
		_check(a.distance_to(b) < .0001, "Scaled off-center cabinet sides meet at angle %s" % angle)
		target.free()
		source.free()
	var target := _node(Vector3.ZERO)
	var source := _node(Vector3.ZERO)
	var deep := AABB(Vector3(-.5, 0, -.5), Vector3(1, 2, 1))
	var shallow := AABB(Vector3(-.5, 0, -.5), Vector3(1, 2, .5))
	var result := SNAP.position_for(source, shallow, Vector3(1.15, 0, .1), [{"node": target, "bounds": deep}])
	_check(result.is_equal_approx(Vector3(1, 0, 0)), "Unequal-depth cabinets share their rear plane")
	source.set_meta("planning_wall_mount", true)
	source.set_meta("planning_wall_normal", Vector3.BACK)
	target.set_meta("planning_wall_mount", true)
	target.set_meta("planning_wall_normal", Vector3.BACK)
	result = SNAP.position_for(source, shallow, Vector3(1.15, .1, 0), [{"node": target, "bounds": deep}], true)
	_check(result.is_equal_approx(Vector3(1, 0, 0)), "Wall cabinet sides and bottoms align")
	target.set_meta("planning_wall_normal", Vector3.FORWARD)
	var value := Vector3(1.15, 0, 0)
	_check(SNAP.position_for(source, shallow, value, [{"node": target, "bounds": deep}], true) == value, "Opposite wall faces never join")
	target.free()
	source.free()

func _test_walls() -> void:
	var box := AABB(Vector3(-1.03, 0, -.15), Vector3(2.06, 2.8, .3))
	var target := _node(Vector3.ZERO, 0, true)
	var source := _node(Vector3.ZERO, 0, true)
	var result := SNAP.position_for(source, box, Vector3(2.2, 0, 0), [{"node": target, "bounds": box}])
	_check(is_equal_approx(result.x, 2.06 - SNAP.WALL_OVERLAP), "Straight walls overlap by 1mm")
	source.rotation.y = PI / 2
	for x in [0.0, 1.03]:
		result = SNAP.position_for(source, box, Vector3(x, 0, -1.15), [{"node": target, "bounds": box}])
		var source_box := Transform3D(source.basis, result) * box
		var target_box := target.global_transform * box
		_check(source_box.intersection(target_box).size.z >= .15, "T/corner junction covers neighbor half-thickness")
	target.free()
	source.free()

func _wall(size: Vector3, position: Vector3, angle: float = 0.0) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = 3
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	wall.add_child(collision)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	wall.add_child(mesh)
	stage.add_child(wall)
	wall.position = position
	wall.rotation.y = angle
	return wall

func _test_floor_walls() -> void:
	var rear := _wall(Vector3(8, 3, .3), Vector3(0, 1.5, -1))
	var side := _wall(Vector3(.3, 3, 8), Vector3(1, 1.5, 0))
	var item := _node(Vector3.ZERO)
	var box := AABB(Vector3(-.5, 0, -.4), Vector3(1, 2, .8))
	await physics_frame
	var result := FLOOR.position_for(item, box, Vector3(.15, 0, -.15))
	_check(absf(result.x - (.35 - FLOOR.CLEARANCE)) < .0001, "Floor object end is flush against side wall")
	_check(absf(result.z - (-.45 + FLOOR.CLEARANCE)) < .0001, "Floor object back is flush against rear wall in the same corner")
	rear.free()
	side.free()
	var angle := PI / 4
	var rotated := _wall(Vector3(8, 3, .3), Basis(Vector3.UP, angle) * Vector3(0, 1.5, -1), angle)
	item.rotation.y = angle
	await physics_frame
	result = FLOOR.position_for(item, box, item.basis * Vector3(0, 0, -.15))
	_check(absf((item.basis.inverse() * result).z - (-.45 + FLOOR.CLEARANCE)) < .0001, "Rotated object uses oriented back plane")
	rotated.free()
	item.free()

func _test_cabinets() -> void:
	var catalog := CATALOG.new()
	var geometry := GEOMETRY.new()
	for name in ["02_capboard_down_destructible.glb", "02_capboard_up_double_destructible.glb"]:
		var path: String = "res://models/objects/enviroments/02/" + name
		var target := catalog._instantiate_asset(path)
		var source := catalog._instantiate_asset(path)
		stage.add_child(target)
		stage.add_child(source)
		var bounds: AABB = geometry._combined_aabb(source)
		var visual := source.get_node("Visual") as Node3D
		var authored: AABB = geometry._combined_aabb(visual)
		_check(bounds.is_equal_approx(authored), "Contact shadow does not widen cabinet placement bounds")
		var mounted := bool(source.get_meta("planning_wall_mount", false))
		if mounted:
			source.set_meta("planning_wall_normal", Vector3.BACK)
			target.set_meta("planning_wall_normal", Vector3.BACK)
		var result := SNAP.position_for(source, bounds, Vector3(bounds.size.x + .15, 0, 0), [{"node": target, "bounds": geometry._combined_aabb(target)}], mounted)
		_check(absf(result.x - bounds.size.x) < .0001, "Real imported cabinet sides meet: " + name)
		target.free()
		source.free()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _capture_contacts() -> void:
	if DisplayServer.get_name() == "headless":
		return
	root.size = Vector2i(640, 480)
	root.positional_shadow_atlas_size = 256
	RenderingServer.directional_shadow_atlas_set_size(256, true)
	var geometry := GEOMETRY.new()
	var catalog := CATALOG.new()
	var walls: Array[Node3D] = []
	for point in [Vector3(0, 0, -1), Vector3(2.12, 0, -1), Vector3(3.1, 0, 0)]:
		var wall := catalog._instantiate_asset("res://game/presentation/office_floor/public/structural/wall_straight.tscn")
		stage.add_child(wall)
		wall.position = point
		if walls.size() == 2:
			wall.rotation.y = PI / 2
		var neighbors: Array[Dictionary] = []
		for other: Node3D in walls:
			neighbors.append({"node": other, "bounds": geometry._combined_aabb(other)})
		wall.position = SNAP.position_for(wall, geometry._combined_aabb(wall), point, neighbors)
		walls.append(wall)
	_wall(Vector3(12, .1, 9), Vector3(0, -.05, 0))
	for index in 2:
		var cabinet := catalog._instantiate_asset("res://models/objects/enviroments/02/02_capboard_down_destructible.glb")
		stage.add_child(cabinet)
		cabinet.freeze = true
		var bounds: AABB = geometry._combined_aabb(cabinet)
		cabinet.position = Vector3(float(index) * bounds.size.x, -bounds.position.y, 0)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(-5, 6, 8)
	camera.look_at(Vector3(1, 1, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.0
	camera.current = true
	var light := DirectionalLight3D.new()
	stage.add_child(light)
	light.rotation_degrees = Vector3(-60, -25, 0)
	light.light_energy = 1.4
	var environment := WorldEnvironment.new()
	stage.add_child(environment)
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.12, .15, .18)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .45
	for index in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(not image.is_empty(), "Native contact fixture renders")
	image.save_png("/tmp/planner_contacts_" + RenderingServer.get_current_rendering_method() + ".png")
