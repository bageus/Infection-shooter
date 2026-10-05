extends SceneTree
const MAIN := preload("res://game/bootstrap/app/main.tscn")
const POOL := preload("res://game/features/combat/public/impact_effects.gd")
const PISTOL := preload("res://game/features/combat/public/pistol.tscn")
const BLOOD := preload("res://game/presentation/office_floor/public/props/blood_decal.tscn")
const DECOR := preload("res://game/bootstrap/app/planning_decor_poses.gd")
const CORPSE := preload("res://game/features/infected/public/decor/corpse_hunger.tscn")
const PART := preload("res://game/features/infected/public/decor/part_hunger_arm.tscn")
class SoftBody:
	extends StaticBody3D
	func get_projectile_material(_shape_index: int = -1) -> String:
		return "wood"

var failures := 0
var stage: Node3D
var pool: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	pool = POOL.new()
	stage.add_child(pool)
	_setup_capture()
	await _projection()
	await _muzzle_guard()
	await _poses()
	stage.queue_free()
	await process_frame
	await _planner_roundtrip()
	print("Surface/pose tests: %d failures" % failures)
	quit(failures)


func _box(position: Vector3, size: Vector3, glass: bool = false) -> StaticBody3D:
	var body := StaticBody3D.new()
	stage.add_child(body)
	body.position = position
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	var visual := MeshInstance3D.new()
	visual.name = "Glass" if glass else "Receiver"
	visual.mesh = BoxMesh.new()
	visual.mesh.size = size
	if glass:
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = .5
		visual.mesh.material = material
	body.add_child(visual)
	return body


func _projection() -> void:
	var end := _box(Vector3(0, 1, -1), Vector3(.16, 2, .2))
	var left := _box(Vector3(3.5, 1, -1), Vector3(1, 2, .2))
	var right := _box(Vector3(4.5, 1, -1), Vector3(1, 2, .2))
	var glass := _box(Vector3(8, 1, -1), Vector3(1, 2, .2), true)
	var table := _box(Vector3(12, .7, 0), Vector3(.8, .1, .8))
	var chair := _box(Vector3(12.7, .7, 0), Vector3(.5, .1, .5))
	await physics_frame
	await physics_frame
	var projector := Transform3D(Basis.IDENTITY, Vector3(0, 1, -.9))
	var entries: Array = pool.call("projected_geometry", end, projector, Vector2.ONE * 1.5, .18, true)
	_check(entries.size() == 1, "Narrow wall end receives one clipped surface")
	for entry in entries:
		for vertex in entry["mesh"].get_faces():
			_check(absf(vertex.x) <= .0801 and vertex.z > 0, "End decal never overhangs the width or crosses to rear face")
	projector.origin.x = 4.0
	entries = pool.call("projected_geometry", left, projector, Vector2(1.6, 1.0), .18, true)
	_check(entries.size() == 2, "A single stamp continues onto adjacent receiver")
	var seams: Array[float] = []
	for entry in entries:
		var arrays: Array = entry["mesh"].surface_get_arrays(0)
		for index in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
			var world: Vector3 = entry["anchor"].global_transform * arrays[Mesh.ARRAY_VERTEX][index]
			if absf(world.x - 4.0) < .0001:
				seams.append(arrays[Mesh.ARRAY_TEX_UV][index].x)
	_check(seams.size() >= 4 and seams.all(func(value: float) -> bool: return absf(value - .5) < .0001), "Both objects share the same image coordinates at their seam")
	projector.origin.x = 8.0
	_check((pool.call("projected_geometry", glass, projector, Vector2.ONE, .18, true) as Array).is_empty(), "Scorch rejects glass")
	var blood := BLOOD.instantiate() as Node3D
	blood.call("configure_world", stage, pool)
	blood.call("configure_blood", "splatter_01", "object")
	stage.add_child(blood)
	blood.global_position = Vector3(12.39, .75, 0)
	blood.call("configure_blood_normal", Vector3.UP)
	blood.call("attach_blood", table.get_child(1), "table_test")
	var visual := blood.get_node("BloodQuad") as MeshInstance3D
	_check(visual.mesh is ArrayMesh and visual.mesh.get_surface_count() == 2, "Blood at table edge clips to table and adjacent chair")
	for vertex in visual.mesh.get_faces():
		var point := visual.global_transform * vertex
		_check(point.y > .75 and point.y < .78, "Blood follows actual seat/table top, never floats on a bounding plane")
	await _capture("blood_table_chair", blood.global_position)
	blood.queue_free()
	for body in [end, left, right, glass, table, chair]:
		body.queue_free()
	await process_frame


func _muzzle_guard() -> void:
	var shooter := CharacterBody3D.new()
	stage.add_child(shooter)
	shooter.position = Vector3(0, 1.2, 0)
	var pivot := Node3D.new()
	shooter.add_child(pivot)
	var gun := PISTOL.instantiate() as Node3D
	pivot.add_child(gun)
	gun.position.z = -.65 # The animated hand/grip has already crossed the wall.
	gun.call("configure_world", stage, pool)
	gun.set("spread_degrees", 0.0)
	var soft := SoftBody.new()
	stage.add_child(soft)
	soft.position = Vector3(0, 1.2, -.18)
	var soft_shape := CollisionShape3D.new()
	soft_shape.shape = BoxShape3D.new()
	soft_shape.shape.size = Vector3(1, 1, .06)
	soft.add_child(soft_shape)
	var wall := _box(Vector3(0, 1.2, -.4), Vector3(2, 2, .08))
	await physics_frame
	await physics_frame
	_check(gun.call("try_fire_at", Vector3(0, 1.2, -5)), "Obstructed shot still spends ammunition")
	await process_frame
	_check(stage.get_children().all(func(node: Node) -> bool: return node.scene_file_path != "res://game/features/combat/public/prototype_bullet.tscn"), "No bullet appears beyond a wall even when both grip and muzzle are beyond it")
	_check(not (pool.get("_marks") as Array).is_empty(), "Obstruction receives the impact")
	soft.queue_free()
	wall.queue_free()
	shooter.queue_free()
	await process_frame


func _poses() -> void:
	var bounds: Dictionary = {}
	for pose in ["back", "stomach", "left_side", "right_side", "seated", "seated_side"]:
		var corpse := CORPSE.instantiate() as Node3D
		corpse.call("configure_decor_pose", {"seed": 2, "pose": pose, "facing": 0.0})
		stage.add_child(corpse)
		var box: AABB = corpse.call("get_planner_bounds")
		_check(absf(box.position.y) < .0001, "Posed corpse is grounded: " + pose)
		bounds[pose] = box
		await _capture("corpse_" + pose, box.get_center())
		await process_frame
		corpse.queue_free()
		await process_frame
	_check(bounds["seated"].size.y > bounds["back"].size.y * 1.3, "Sitting and lying corpses have genuinely different silhouettes")
	var horde: Node3D = load("res://game/features/infected/public/decor/corpse_horde.tscn").instantiate()
	horde.call("configure_decor_pose", {"seed": 6, "pose": "stomach", "facing": .3})
	stage.add_child(horde)
	_check((horde.get_node("Body") as Node3D).scale.is_equal_approx(Vector3.ONE * 2.21), "Random poses preserve the authored Horde scale")
	horde.queue_free()
	await process_frame
	var wall := _box(Vector3(5, 1, 0), Vector3(3, 2, .2))
	await physics_frame
	await physics_frame
	var seated := CORPSE.instantiate() as Node3D
	seated.call("configure_decor_pose", {"seed": 2, "pose": "auto"})
	stage.add_child(seated)
	seated.position = Vector3(5, .016, .6)
	DECOR.place(seated)
	_check(seated.call("get_decor_pose")["pose"] == "seated", "Nearby wall enables an authored seated pose")
	var orientations: Array[Basis] = []
	for seed_value in [31, 43]:
		var part := PART.instantiate() as Node3D
		part.call("configure_decor_pose", {"seed": seed_value})
		stage.add_child(part)
		part.set("freeze", true)
		orientations.append((part.get_child(0) as Node3D).basis)
		part.queue_free()
		await process_frame
	_check(not orientations[0].is_equal_approx(orientations[1]), "Parts receive seeded XYZ orientations")
	seated.queue_free()
	wall.queue_free()
	await process_frame


func _planner_roundtrip() -> void:
	var game := MAIN.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	var authored: SceneState = load("res://game/presentation/office_floor/public/base_office_layout.tscn").get_state()
	for node_index in authored.get_node_count():
		var properties: Dictionary = {}
		for property_index in authored.get_node_property_count(node_index):
			properties[str(authored.get_node_property_name(node_index, property_index))] = authored.get_node_property_value(node_index, property_index)
		var script: Variant = properties.get("script")
		if script is Script and script.resource_path.ends_with("/planner_light.gd"):
			var lamp: Node3D = load("res://game/presentation/office_floor/public/props/planner_light.tscn").instantiate()
			for key in properties:
				if key != "script":
					lamp.set(key, properties[key])
			game.get_node("Structure").add_child(lamp)
	game.call("_on_planning_pressed")
	var planner: Node = game.get("planning_mode")
	var objects: Node = planner.get("objects")
	var controls: Node = planner.get("controls")
	objects.call("_register_existing_scene_objects")
	var inspected := 0
	for lamp: Node3D in (objects.get("placed") as Array):
		if not lamp.has_method("get_fixture_config"):
			continue
		objects.call("_select", lamp)
		_check(controls.fixtures.selected_panel.visible and controls.selected_light_color.get_parent().visible and controls.light_info.visible, "Installed lamp exposes fixture/color/energy parameters")
		inspected += 1
	_check(inspected > 10, "Every authored installed lamp was checked")
	var corpse := planner.call("_instantiate_asset", "res://game/features/infected/public/decor/corpse_hunger.tscn") as Node3D
	corpse.call("configure_decor_pose", {"seed": 77, "pose": "stomach", "facing": .7})
	planner.root.add_child(corpse)
	corpse.set_meta("planning_scene_path", "res://game/features/infected/public/decor/corpse_hunger.tscn")
	objects.placed.append(corpse)
	var expected: Dictionary = corpse.call("get_decor_pose")
	var history: RefCounted = planner.get("edit_history")
	objects.call("_select", corpse)
	history.call("duplicate_selected")
	_check(objects.selected.call("get_decor_pose") == expected, "Duplicate keeps corpse pose")
	var data: Dictionary = planner.storage._collect_layout_data()
	objects.call("_apply_layout_data", data)
	await process_frame
	var records: Array = planner.storage._collect_layout_data()["objects"].filter(func(record: Dictionary) -> bool: return record.has("decor_pose"))
	_check(records.size() == 2 and records.all(func(record: Dictionary) -> bool: return record["decor_pose"] == expected), "Optional DTO v8 corpse poses survive full map roundtrip")
	planner.call("exit")
	game.queue_free()
	await process_frame
	await process_frame


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _setup_capture() -> void:
	if OS.get_environment("POSE_CAPTURE_DIR").is_empty() or DisplayServer.get_name() == "headless":
		return
	var camera := Camera3D.new()
	camera.name = "EvidenceCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.5
	stage.add_child(camera)
	camera.current = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.14, .16, .2)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .7
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	stage.add_child(light)
	light.rotation_degrees = Vector3(-45, -30, 0)


func _capture(label: String, target: Vector3) -> void:
	var camera := stage.get_node_or_null("EvidenceCamera") as Camera3D
	if camera == null:
		return
	camera.global_position = target + Vector3(2, 2, 3)
	camera.look_at(target)
	await process_frame
	await RenderingServer.frame_post_draw
	var directory := OS.get_environment("POSE_CAPTURE_DIR")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_texture().get_image().save_png(directory.path_join(label + "_" + RenderingServer.get_current_rendering_method() + ".png"))
