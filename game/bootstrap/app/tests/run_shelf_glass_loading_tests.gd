extends SceneTree
## Solid shelves, hidden-start glass and pre-play material preparation.
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const WORKSTATIONS := preload("res://game/bootstrap/app/workstation_templates.gd")
const VISUALS := preload("res://game/bootstrap/app/desk_setup_visuals.gd")
const WARMUP := preload("res://game/bootstrap/app/mission_material_warmup.gd")
const CLOUD := preload("res://game/features/infection_source/public/mutagen_cloud.tscn")
const GLASS := preload("res://game/presentation/office_floor/public/structural/glass_wall_full.tscn")
const ROOT := "res://models/objects/enviroments/"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	await _shelves(stage)
	await _hidden_glass(stage)
	await _materials(stage)
	await _cloud_height(stage)
	stage.queue_free()
	await process_frame
	print("Shelf/glass/loading tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _shelves(stage: Node3D) -> void:
	for model in WORKSTATIONS.DESKS:
		if not ("book_case" in str(model) or "bookshelf" in str(model) or "with_shelfs" in str(model)):
			continue
		var shelf := PROP.instantiate() as RigidBody3D
		shelf.set("model_path", ROOT + "03/" + str(model) + ".glb")
		stage.add_child(shelf)
		_check_mass(shelf)
		_check(not shelf.continuous_cd, "Full-size shelf does not acquire small-prop CCD from decomposed boards")
		shelf.freeze = true
		shelf.rotation.y = .6
		shelf.scale = Vector3.ONE * 1.1
		await physics_frame
		await physics_frame
		var profile := WORKSTATIONS.profile(str(model) + ".glb")
		# Planner zones and objects use the measured board tops, not the authored heights.
		var visuals := VISUALS.new()
		shelf.set_meta("planning_scene_path", ROOT + "03/" + str(model) + ".glb")
		visuals.call("configure", shelf, profile)
		var tops: Array = visuals.call("_board_tops", shelf)
		for station_value in visuals.get("stations"):
			var planned := float((station_value as Dictionary).get("grid_height", 0.0))
			var nearest := INF
			for top in tops:
				nearest = minf(nearest, absf(float(top) - planned))
			_check(nearest < .003, "%s planner level %.3f sits on a board top" % [model, planned])
		visuals.free()
		var supported := 0
		var books: Array[RigidBody3D] = []
		for station: Dictionary in profile.stations:
			var height := float(station.grid_height)
			var start := shelf.to_global(Vector3(float(station.x), height + .13, float(station.z)))
			var end := shelf.to_global(Vector3(float(station.x), height - .16, float(station.z)))
			var query := PhysicsRayQueryParameters3D.create(start, end)
			var hit := stage.get_world_3d().direct_space_state.intersect_ray(query)
			_check(hit.get("collider") == shelf, "%s has a physical surface at %.2f" % [model, height])
			if hit.get("collider") != shelf:
				continue
			var clearance_start := shelf.to_global(Vector3(float(station.x), height + .15, float(station.z)))
			var clearance_end := shelf.to_global(Vector3(float(station.x), height + .11, float(station.z)))
			var clearance := stage.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(clearance_start, clearance_end))
			_check(clearance.get("collider") != shelf, "%s keeps the opening above each shelf" % model)
			supported += 1
			var book := PROP.instantiate() as RigidBody3D
			book.set("model_path", ROOT + "09/09_book_small.glb")
			stage.add_child(book)
			book.global_position = hit.position + Vector3.UP * .08
			book.rotation.y = shelf.rotation.y
			book.global_position.y += (hit.position as Vector3).y + .04 - WORKSTATIONS._bounds(book).position.y
			book.set_meta("expected_bottom", (hit.position as Vector3).y)
			books.append(book)
		_check(supported == profile.stations.size(), "Every authored shelf supports a book")
		_check((shelf.get("_shapes") as Array).size() <= 32, "%s collision stays bounded (%d)" % [model, (shelf.get("_shapes") as Array).size()])
		for tick in 120:
			await physics_frame
		for book in books:
			var bounds := WORKSTATIONS._bounds(book)
			var expected := float(book.get_meta("expected_bottom"))
			_check(absf(bounds.position.y - expected) < .07, "%s book rests on shelf: %.3f vs %.3f" % [model, bounds.position.y, expected])
			book.free()
		shelf.free()


func _check_mass(shelf: RigidBody3D) -> void:
	var seen: Dictionary = {}
	var volume := 0.0
	for mesh: MeshInstance3D in shelf.get("_shape_meshes"):
		if seen.has(mesh.get_instance_id()):
			continue
		seen[mesh.get_instance_id()] = true
		var local := shelf.global_transform.affine_inverse() * mesh.global_transform
		volume += mesh.get_aabb().get_volume() * absf(local.basis.determinant())
	_check(is_equal_approx(shelf.mass, clampf(volume * 18.0, .12, 55.0)), "Board collision decomposition preserves the original model mass estimate")


func _hidden_glass(stage: Node3D) -> void:
	stage.hide()
	var glass := GLASS.instantiate() as Node3D
	stage.add_child(glass)
	var body := glass.get_node("GlassBody")
	var panes: Array = body.get("_glass_nodes")
	_check(not panes.is_empty(), "Hidden mission registers its glass panes")
	stage.show()
	body.call("take_projectile_hit", 100.0, Vector3.ZERO, Vector3.FORWARD, Vector3.FORWARD, "GRENADE")
	await process_frame
	for pane: Node3D in panes:
		_check(not pane.visible and not pane.is_visible_in_tree(), "Broken glass remains visually absent after hidden startup")
	_check(body.collision_layer == 0, "Broken pane is also absent from collision")
	glass.free()


func _materials(stage: Node3D) -> void:
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.make_current()
	var material := StandardMaterial3D.new()
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.GREEN)
	material.albedo_texture = ImageTexture.create_from_image(image)
	for index in 3:
		var visual := MeshInstance3D.new()
		visual.mesh = BoxMesh.new()
		visual.material_override = material
		stage.add_child(visual)
	var warmup := WARMUP.new()
	var phases: Array[String] = []
	paused = true
	await warmup.prepare(stage, camera, self, func(_value: float, phase: String) -> void: phases.append(phase))
	_check(paused, "Material preparation completes before gameplay resumes")
	_check(warmup.material_count == 1 and warmup.batch_count == 1, "Shared material uploads once")
	_check("materials" in phases and camera.get_node_or_null("MissionMaterialWarmup") == null, "Loading phase is reported and samples are removed")
	_check(material.albedo_texture != null, "Warmup preserves authored materials")
	paused = false


func _cloud_height(stage: Node3D) -> void:
	var floor := StaticBody3D.new()
	stage.add_child(floor)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, .1, 10)
	collision.shape = box
	floor.add_child(collision)
	floor.position.y = -.05
	var cloud := CLOUD.instantiate() as Area3D
	stage.add_child(cloud)
	cloud.position.y = 1.0 # Spawn at the enemy body pivot, not the ground.
	await physics_frame
	await physics_frame
	cloud.call("activate")
	var visual := cloud.get_node("Visual") as GeometryInstance3D
	var center: Vector3 = (visual.material_override as ShaderMaterial).get_shader_parameter("cloud_center")
	_check(absf(center.y) < .01, "Cloud height uses the floor below the enemy pivot")
	var shape := cloud.get_node("CollisionShape3D") as CollisionShape3D
	_check(absf(shape.global_position.y - 1.25) < .01 and is_equal_approx((shape.shape as CylinderShape3D).height, 1.5), "Absorption volume spans 0.5 to 2 metres")
	var material := visual.material_override as ShaderMaterial
	_check("v_world_position.y < cloud_center.y + 0.5" in material.shader.code and "v_world_position.y > cloud_center.y + 2.0" in material.shader.code, "Smoke clips in world height throughout its lifecycle")


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
