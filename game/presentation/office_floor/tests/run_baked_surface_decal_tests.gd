extends SceneTree
const FLOOR := preload("res://game/presentation/office_floor/public/base_floor_renderer.gd")
const CONFIG := preload("res://game/presentation/office_floor/public/surface_decal_config.gd")
const BAKE := preload("res://game/presentation/office_floor/receiver_decal_bake.gd")
const PIXELS := preload("res://game/presentation/office_floor/decal_pixels.gd")
const EVENTS := preload("res://game/presentation/office_floor/surface_decal_events.gd")
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
var failures := 0
var stage: Node3D
var floor_view: Node3D

func _init() -> void: call_deferred("_run")

func _run() -> void:
	_test_config()
	stage = Node3D.new()
	root.add_child(stage)
	floor_view = FLOOR.new()
	stage.add_child(floor_view)
	_test_pixels()
	if DisplayServer.get_name() == "headless":
		await _test_receivers()
		_test_fresh_receivers()
		await _test_persistence()
		await _test_glass()
		await _test_displays()
		_test_steps()
	else:
		# Real-model hooks run headlessly above; native QA isolates the new shader.
		await _test_render()
	floor_view.call("clear_glass_debris")
	for voice in stage.find_children("*", "AudioStreamPlayer3D", true, false): (voice as AudioStreamPlayer3D).stop()
	stage.queue_free()
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless": await create_timer(0.25).timeout
	print("Baked surface decal tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _test_config() -> void:
	_check(CONFIG.valid({}) and CONFIG.valid({"glass": {"opacity": 0.3, "size": 1.5}}), "Legacy/authored settings valid")
	for invalid: Variant in [[], {"glass": []}, {"glass": {"opacity": NAN}}, {"glass": {"size": 0}}, {"bad": {}}, {"glass": {"alpha": 1}}]:
		_check(not CONFIG.valid(invalid), "Malformed config rejected")
	var config := CONFIG.normalized({"glass": {"opacity": INF, "size": -5}})
	_check(config.glass.opacity == 0.65 and config.glass.size == 0.25, "Direct commands clamp invalid values")
	_check(CONFIG.normalized({}).floor_scuff.opacity < 0.2, "Default foot scuffs faint")

func _test_pixels() -> void:
	var bake: RefCounted = floor_view.get("_glass")
	var cache: RefCounted = bake.get("_atlases")
	for kind: String in cache.SURFACE_DEFINITIONS:
		_check(cache.sources[kind].size() == (8 if kind in ["bullet", "glass_impact"] else 16), "Every atlas frame loaded")
		for source: Image in cache.sources[kind]: _check(source.get_used_rect().has_area(), "Source pixels visible")
	var original: Image = cache.sources.floor_damage[0]
	var before := hash(original.get_data())
	_check(_alpha(PIXELS.source(original, 0.2)) < _alpha(original) * 0.22 and hash(original.get_data()) == before, "Opacity changes alpha, not the source")
	var white := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	_check(_alpha(PIXELS.source(white, 1, 0, true)) == 0, "Scorch removes white atlas background")
	white.fill(Color.BLACK)
	_check(_alpha(PIXELS.source(white, 1, 0, true)) > 0, "Scorch retains soot")
	var nodes := floor_view.get_child_count()
	floor_view.call("stamp_glass_debris", Vector2(2, 2), 10, 1.0)
	while bake.step(): pass
	var cell: Vector2i = bake.cell_at(Vector2(2, 2))
	var debris_hash := hash(bake.tiles[cell].image.get_data())
	floor_view.call("stamp_floor_surface", Vector2(2, 2), "floor_scuff", 3, 1.0)
	floor_view.call("stamp_floor_surface", Vector2(2, 2), "floor_damage", 10, 1.0)
	while bake.step(): pass
	_check(hash(bake.tiles[cell].image.get_data()) == debris_hash, "Late lower layers never overwrite debris")
	_check(bake.tiles[cell].layers.size() == 2 and bake.tiles[cell].layers[0].image.get_width() == 256, "Independent compact lower layers")
	_check(_alpha(bake.tiles[cell].layers[0].image) > 0 and _alpha(bake.tiles[cell].layers[1].image) > 0, "Damage and scuff pixels visible")
	_check(floor_view.get_child_count() == nodes, "Floor adds no per-mark nodes")
	floor_view.call("clear_glass_debris")

func _test_fresh_receivers() -> void:
	# A receiver overlay must sample real decal textures from its first frame; an unset sampler reads white.
	var baker: RefCounted = floor_view.get("_surface_events").receivers
	var anchors: Array[MeshInstance3D] = [_box(Vector3(-40, 1, 0)), _box(Vector3(-40, 1, 3))]
	for anchor in anchors: baker.stamp(anchor, anchor.position, Vector3.BACK, "wall_damage", 3, 0.6, 0.5)
	baker.step()
	for anchor in anchors:
		var material := anchor.material_overlay as ShaderMaterial
		_check(material != null and material.get_shader_parameter("damage") != null and material.get_shader_parameter("scuffs") != null, "New receiver overlay is textured before the next upload")
	while baker.step(): pass

func _test_receivers() -> void:
	var baker: RefCounted = floor_view.get("_surface_events").receivers
	var anchors: Array[MeshInstance3D] = []
	for index in 18:
		var anchor := _box(Vector3(index * 2, 1, 0))
		anchors.append(anchor)
		baker.stamp(anchor, anchor.position, Vector3.BACK, "wall_damage", index % 16, 0.6, 0.5)
	while baker.step(): pass
	_check(baker.pages.size() == BAKE.MAX_RECEIVERS and anchors[0].material_overlay == null, "LRU bounds receiver storage and releases overlays")
	var last := anchors[-1]
	var material := last.material_overlay
	baker.stamp(last, last.position, Vector3.BACK, "wall_scuff", 0, 0.8, 0.1)
	while baker.step(): pass
	_check(last.material_overlay == material and last.get_child_count() == 0, "Repeated wall hits reuse a single overlay")
	var uploads: int = baker.uploads
	baker.step()
	_check(baker.uploads == uploads, "Idle receiver cache does not upload")
	_check(_alpha(baker.pages[last.get_instance_id()].layers[1].image) > 0, "Wall scuff layer visible")
	last.hide()
	_check(last.material_overlay == null, "Hidden/destroyed receiver clears immediately")
	baker.clear()
	for anchor in anchors: anchor.queue_free()
	await process_frame

func _test_persistence() -> void:
	var bake: RefCounted = load("res://game/presentation/office_floor/glass_floor_bake.gd").new(func(_cell: Vector2i, _texture: Texture2D) -> void: pass)
	bake.stamp(Vector2(4, 4), 0, 0.5, 0, "bullet")
	while bake.step(): pass
	for index in bake.MAX_TILES + 2:
		bake.stamp(Vector2(12 + index * 8, 4), 0, 0.5, 0, "bullet")
		while bake.step(): pass
	_check(not bake.tiles.has(Vector2i.ZERO), "Floor cell evicted from the GPU set")
	bake.stamp(Vector2(4, 4), 0, 0.25, 0, "bullet")
	while bake.step(): pass
	_check(_alpha(bake.tiles[Vector2i.ZERO].layers[0].image.get_region(Rect2i(96, 96, 64, 64))) > 0 and bake.tiles[Vector2i.ZERO].texture != null, "Evicted floor decal pixels restored")
	var baker: RefCounted = BAKE.new()
	baker.sources = floor_view.get("_surface_events").receivers.sources
	var anchors: Array[MeshInstance3D] = []
	for index in BAKE.MAX_RECEIVERS + 3:
		anchors.append(_box(Vector3(index * 2, 1, 0)))
		baker.stamp(anchors[-1], anchors[-1].position, Vector3.BACK, "wall_damage", 0, 0.6, 0.5)
		while baker.step(): pass
	_check(not baker.pages.has(anchors[0].get_instance_id()), "Wall page evicted from the GPU set")
	baker.stamp(anchors[0], anchors[0].position, Vector3.BACK, "wall_scuff", 0, 0.3, 0.5)
	while baker.step(): pass
	_check(_alpha(baker.pages[anchors[0].get_instance_id()].layers[0].image) > 0, "Evicted wall decal layer restored")
	for index in BAKE.MAX_ARCHIVE + BAKE.MAX_RECEIVERS:
		anchors.append(_box(Vector3(index * 2, 3, 0)))
		baker.stamp(anchors[-1], anchors[-1].position, Vector3.BACK, "wall_damage", 0, 0.6, 0.5)
		while baker.step(): pass
	_check(baker.get("_archive").size() == BAKE.MAX_ARCHIVE, "Released wall archive stays bounded")
	baker.clear()
	for anchor in anchors: anchor.queue_free()
	await process_frame

func _test_glass() -> void:
	var scene := load("res://game/presentation/office_floor/public/structural/glass_wall_full.tscn").instantiate() as Node3D
	stage.add_child(scene)
	scene.call("configure_glass_debris", floor_view)
	await physics_frame
	var glass := scene.get_node("GlassBody") as StaticBody3D
	var pane := (glass.get("_glass_nodes") as Array)[0] as MeshInstance3D
	var point := pane.to_global(pane.get_aabb().get_center())
	var normal := _normal(pane)
	glass.call("take_projectile_hit", 30.0, point, normal, -normal, "PISTOL")
	var baker: RefCounted = floor_view.get("_surface_events").receivers
	var corners := 0
	for request: Dictionary in baker.queue:
		if request.kind == "glass_fracture" and request.size > 0.3:
			_check(request.frame in [0, 1, 2, 12, 13], "Owner-selected sparse cells spread over the pane")
			if request.frame == 13: corners += 1
	_check(corners == 4 and glass.call("crack_count") == 1, "First impact adds four rotated corners and one factual crack")
	while baker.step(): pass
	_check(pane.material_overlay != null, "Glass uses a baked texture")
	baker.clear() # Simulate bounded receiver eviction while the pane stays alive.
	var before := glass.get_child_count()
	glass.call("take_projectile_hit", 30.0, point, normal, -normal, "PISTOL")
	_check(glass.get_child_count() == before, "Another glass hit adds no decal node")
	_check(baker.queue.filter(func(request: Dictionary) -> bool: return request.kind == "glass_fracture" and request.frame == 13).size() == 4, "Recreated receiver restores its corner fissures")
	glass.call("take_projectile_hit", 100.0, point, normal, -normal, "GRENADE")
	while baker.step(): pass
	_check(glass.call("crack_count") == 0 and pane.material_overlay == null, "Shatter clears every glass mark")
	scene.queue_free()
	await process_frame
	floor_view.call("clear_glass_debris")

func _test_displays() -> void:
	for path: String in ["05_monitor_destructible.glb", "05_wall_TV_destructible.glb"]:
		var prop := PROP.instantiate() as RigidBody3D
		prop.set("model_path", "res://models/objects/enviroments/05/" + path)
		stage.add_child(prop)
		prop.freeze = true
		prop.call("configure_glass_debris", floor_view)
		await physics_frame
		var display := prop.get("_display") as Node3D
		var mesh := (display.get("screens") as Array)[0].mesh as MeshInstance3D
		var point := mesh.to_global(mesh.get_aabb().get_center())
		var normal := _normal(mesh)
		prop.call("take_projectile_hit", 1.0, point, normal, -normal, "PISTOL")
		var baker: RefCounted = floor_view.get("_surface_events").receivers
		while baker.step(): pass
		_check(display.is_visible_in_tree() and not display.get("powered") and mesh.material_overlay != null, "%s keeps cracks after power loss" % path)
		prop.queue_free()
		await process_frame
		floor_view.call("clear_glass_debris")

func _test_steps() -> void:
	for weapon: String in ["SNIPER", "SHOTGUN", "AK", "M4", "MINIGUN", "GRENADE"]:
		_check(EVENTS.powerful(weapon), "Heavy weapon permits occasional structural damage")
	_check(not EVENTS.powerful("PISTOL") and not EVENTS.powerful("UZI"), "Light bullets cannot peel plaster")
	seed(7251)
	var events: RefCounted = floor_view.get("_surface_events")
	for index in 300: events.step_at(Vector3(1, 0, 1), Vector3.UP)
	_check(floor_view.get("_glass").queue.size() <= 2, "Crowd step stamps bounded per physics frame")
	floor_view.call("clear_glass_debris")
	for index in 100: events.step_at(Vector3(1, 3, 1), Vector3.UP)
	_check(floor_view.get("_glass").queue.is_empty(), "Raised support never stains floor underneath")

func _test_render() -> void:
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.5
	camera.look_at_from_position(Vector3(0, 6, 7), Vector3(0, 0.7, 0))
	camera.current = true
	var light := DirectionalLight3D.new()
	stage.add_child(light)
	light.rotation_degrees = Vector3(-60, -25, 0)
	var wall := _box(Vector3(-1.4, 1.1, 0))
	var glass := _box(Vector3(1.4, 1.1, 0))
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.5, 0.6, 0.35)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.material_override = material
	await process_frame
	await RenderingServer.frame_post_draw
	var clean := root.get_texture().get_image()
	floor_view.get("_surface_events").receivers.stamp(wall, wall.position, Vector3.BACK, "wall_damage", 10, 1.1, 0.7)
	floor_view.get("_surface_events").glass_hit(glass, glass.position, Vector3.BACK)
	floor_view.call("stamp_glass_debris", Vector2(0, 2), 10, 1.2)
	floor_view.call("stamp_floor_surface", Vector2(0, 2), "floor_scuff", 0, 1.2)
	floor_view.call("stamp_floor_surface", Vector2(0, 2), "floor_damage", 10, 1.2)
	for frame in 24: await process_frame
	await RenderingServer.frame_post_draw
	var dirty := root.get_texture().get_image()
	var changed := 0
	for y in range(0, dirty.get_height(), 2):
		for x in range(0, dirty.get_width(), 2):
			if not dirty.get_pixel(x, y).is_equal_approx(clean.get_pixel(x, y)): changed += 1
	_check(changed > 100, "Native shaders draw actual baked surface pixels")
	_check(_region_changes(clean, dirty, camera.unproject_position(Vector3(-1.4, 1.1, 0.11)), 55) > 20, "Wall damage is visible on its own receiver")
	_check(_region_changes(clean, dirty, camera.unproject_position(Vector3(1.4, 1.1, 0.11)), 55) > 6, "Glass impact is visible on its own receiver")
	_check(_region_changes(clean, dirty, camera.unproject_position(Vector3(0, 0, 2)), 55) > 20, "Floor layers are visible on the base floor")
	_check(not floor_view.is_processing(), "Both queues return to idle")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		DirAccess.make_dir_recursive_absolute(args[0])
		dirty.save_png(args[0].path_join("baked_surface_decals.png"))
	wall.queue_free()
	glass.queue_free()
	camera.queue_free()
	light.queue_free()

func _region_changes(clean: Image, dirty: Image, center: Vector2, radius: int) -> int:
	var count := 0
	for y in range(maxi(0, int(center.y) - radius), mini(dirty.get_height(), int(center.y) + radius)):
		for x in range(maxi(0, int(center.x) - radius), mini(dirty.get_width(), int(center.x) + radius)):
			if not dirty.get_pixel(x, y).is_equal_approx(clean.get_pixel(x, y)): count += 1
	return count

func _box(at: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.8, 2, 0.2)
	node.mesh = mesh
	stage.add_child(node)
	node.position = at
	return node

func _normal(mesh: MeshInstance3D) -> Vector3:
	var local := Vector3.ZERO
	local[mesh.get_aabb().size.min_axis_index()] = 1
	return (mesh.global_basis.inverse().transposed() * local).normalized()

func _alpha(image: Image) -> float:
	var bytes := image.get_data()
	var total := 0.0
	for index in range(3, bytes.size(), 4): total += bytes[index]
	return total

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
