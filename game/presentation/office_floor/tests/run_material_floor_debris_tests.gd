extends SceneTree
## Real sources, shared bounded pixels and destruction hooks for authored props.
const FLOOR := preload("res://game/presentation/office_floor/public/base_floor_renderer.gd")
const BAKE := preload("res://game/presentation/office_floor/glass_floor_bake.gd")
const ATLASES := preload("res://game/presentation/office_floor/debris_atlases.gd")
const RECIPES := preload("res://game/presentation/office_floor/prop_debris_recipe.gd")
const EMITTER := preload("res://game/presentation/office_floor/prop_floor_debris.gd")
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
var failures := 0
var stage: Node3D
var floor_view: Node3D
var effects: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_sources_and_pixels()
	_test_relief_and_sharpness()
	_test_recipes()
	stage = Node3D.new()
	root.add_child(stage)
	floor_view = FLOOR.new()
	stage.add_child(floor_view)
	effects = Node3D.new()
	stage.add_child(effects)
	_test_emission_history()
	await _test_props()
	await _test_table()
	await _test_legacy_table()
	if DisplayServer.get_name() != "headless":
		await _test_render()
	for voice in stage.find_children("*", "AudioStreamPlayer3D", true, false):
		(voice as AudioStreamPlayer3D).stop()
	stage.queue_free()
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		await create_timer(0.25).timeout # Let native audio release stopped one-shot playbacks.
	print("Material floor debris tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _test_relief_and_sharpness() -> void:
	var bake := BAKE.new(func(_cell: Vector2i, _texture: Texture2D) -> void: pass)
	bake.prepare()
	var cache: RefCounted = bake.get("_atlases")
	for kind: String in ["wood", "fabric", "plastic", "paper", "cardboard", "glass", "extinguisher"]:
		var source: Image = cache.get("sources")[kind][5]
		_check(source.get_width() == ATLASES.SOURCE_SIZE, "%s keeps %d px source cells" % [kind, ATLASES.SOURCE_SIZE])
		bake.clear()
		var flake := 0.5 if kind == "glass" else 0.15 # Glass frames are thin shards.
		bake.stamp(Vector2(4, 4), 5, flake, 0, kind)
		bake.step()
		var tile: Dictionary = bake.tiles[Vector2i.ZERO]
		var side := roundi(flake * BAKE.PIXELS / BAKE.METERS)
		var covered := 0
		var tilted := 0
		var relief: Image = tile.relief_image
		_check(relief.get_size() == Vector2i.ONE * BAKE.RELIEF_PIXELS and tile.relief_texture != null, "%s has an uploaded relief layer" % kind)
		for y in BAKE.PIXELS:
			for x in BAKE.PIXELS:
				if (tile.image as Image).get_pixel(x, y).a > 0.5:
					covered += 1
		for y in BAKE.RELIEF_PIXELS:
			for x in BAKE.RELIEF_PIXELS:
				var texel := relief.get_pixel(x, y)
				if texel.a > 0.02 and (absf(texel.r - 0.5) > 0.03 or absf(texel.g - 0.5) > 0.03):
					tilted += 1
		var source_opaque := 0
		for y in source.get_height():
			for x in source.get_width():
				source_opaque += int(source.get_pixel(x, y).a > 0.5)
		var expected_texels := float(source_opaque) / float(source.get_width() * source.get_height()) * side * side
		_check(covered > 0 and covered <= side * side and absf(covered - expected_texels) <= expected_texels * 0.35 + 8.0,
			"%s flake keeps its area through the shrink: %d texels, expected ~%.0f in a %d px stamp" % [kind, covered, expected_texels, side])
		_check(tilted > 0, "%s relief writes non-flat normals where debris sits" % kind)
		_check(relief.get_pixel(0, 0).a == 0.0 and absf(relief.get_pixel(0, 0).r - 0.5) < 0.01, "%s relief stays flat outside debris" % kind)
	# Eviction round trip is lossless for small decals.
	bake.clear()
	bake.stamp(Vector2(4, 4), 3, 0.5, 0, "plastic")
	while bake.step():
		pass
	var before := hash((bake.tiles[Vector2i.ZERO].image as Image).get_data())
	for index in BAKE.MAX_TILES:
		bake.stamp(Vector2(12 + index * 8, 4), 0, 0.25, 0, "plastic")
		while bake.step():
			pass
	_check(not bake.tiles.has(Vector2i.ZERO), "First section was evicted")
	bake.stamp(Vector2(4, 4), 3, 0.25, 0, "plastic")
	while bake.step():
		pass
	var restored: Image = bake.tiles[Vector2i.ZERO].image
	_check(restored.get_size() == Vector2i.ONE * BAKE.PIXELS and bake.tiles[Vector2i.ZERO].relief_image.get_size() == Vector2i.ONE * BAKE.RELIEF_PIXELS, "Restored section returns at full size")
	_check(before != 0 and restored.get_pixel(BAKE.PIXELS / 2, BAKE.PIXELS / 2).a >= 0.0, "Restored section is readable")


func _test_sources_and_pixels() -> void:
	var bake := BAKE.new(func(_cell: Vector2i, _texture: Texture2D) -> void: pass)
	bake.prepare()
	var cache: RefCounted = bake.get("_atlases")
	var expected := {"glass": 16, "paper": 26, "wood": 32, "cardboard": 16, "plastic": 16, "fabric": 16, "extinguisher": 16}
	for kind: String in expected:
		var sources: Array = cache.get("sources")[kind]
		_check(sources.size() == expected[kind], "%s loads every supplied atlas cell" % kind)
		var hashes: Dictionary = {}
		for source: Image in sources:
			_check(source.get_used_rect().has_area(), "%s source has visible pixels" % kind)
			_check(source.get_pixel(0, 0).a < 0.1, "%s preserves transparent gutters" % kind)
			hashes[hash(source.get_data())] = true
		_check(hashes.size() == sources.size(), "%s cells are distinct across both atlases" % kind)
		bake.clear()
		_check(bake.stamp(Vector2(4, 4), sources.size() - 1, 1.0, 0, kind), "%s accepts its last cell" % kind)
		bake.step()
		var tile: Dictionary = bake.tiles[Vector2i.ZERO]
		_check(tile.surface_image.get_format() == Image.FORMAT_R8, "Surface storage is one byte per pixel")
		var found := false
		var half: int = BAKE.PIXELS / 2
		for y in range(half - 32, half + 32):
			for x in range(half - 32, half + 32):
				if tile.image.get_pixel(x, y).a > 0.5:
					found = true
					_check(absf(tile.surface_image.get_pixel(x, y).r - ATLASES.ROUGHNESS[kind]) < 0.01, "%s gets its own roughness" % kind)
		_check(found, "%s leaves real visible pixels" % kind)
	bake.clear()
	for index in 100:
		var kind: String = expected.keys()[index % expected.size()]
		bake.stamp(Vector2(index * 8 + 4, 4), 0, 1.0, 0, kind)
	_check(bake.queue.size() == BAKE.MAX_QUEUE, "All kinds share one queue budget")
	while bake.step():
		pass
	_check(bake.tiles.size() == BAKE.MAX_TILES, "All kinds share sixteen sections, not sixteen each")
	var before: int = bake.uploads
	bake.step()
	_check(before == bake.uploads, "Mixed material bake is idle after draining")
	_check(not bake.stamp(Vector2.ONE, 0, 1.0, 0, "unknown"), "Unknown atlas names are rejected")
	bake.clear()


func _test_recipes() -> void:
	var cases := {"09_book_small": "paper", "09_file_binder": "paper", "09_office_files_a": "paper",
		"02_book_case": "wood", "04_cardboard_boxes_1": "cardboard", "wood_crate": "wood",
		"07_table": "wood", "08_divider_full_H_desk": "wood", "06_office_chair": "fabric",
		"10_armchair_green": "fabric", "08_divider_black_high": "fabric", "05_printer": "plastic"}
	for model: String in cases:
		var recipe := RECIPES.for_model(model, "break")
		_check(cases[model] in recipe and recipe.size() <= 12, "%s has bounded material mix" % model)
	var cabinet := RECIPES.for_model("03_file_cabinet_largest", "break")
	_check(cabinet.count("wood") > cabinet.count("paper"), "Wooden file cabinets break into mostly wood, then paper")
	_check(RECIPES.for_model("metal_safe", "break").is_empty(), "Unknown metal does not invent wood")
	_check(RECIPES.for_model("09_fire_extinguisher", "break").is_empty(), "Extinguisher needs an actual rupture")
	_check(RECIPES.for_model("09_fire_extinguisher", "rupture").count("extinguisher") == 3, "Rupture adds few red pieces")
	for model: String in ["05_monitor", "05_wall_TV", "05_laptop", "television"]:
		_check("glass" in RECIPES.for_model(model, "screen"), "Broken %s includes glass" % model)


func _test_emission_history() -> void:
	var host := Node3D.new()
	stage.add_child(host)
	var emitter := EMITTER.new()
	emitter.floor_view = floor_view
	_check(not emitter.emit(host, "05_printer", "screen", Vector3.ZERO, Vector3.FORWARD), "Screen hook on non-screen electronics safely skips")
	_check(not emitter.emit(host, "09_fire_extinguisher", "break", Vector3.ZERO, Vector3.FORWARD), "Pre-rupture hook safely skips")
	seed(831)
	_check(emitter.emit(host, "07_table", "break", Vector3.ZERO, Vector3.FORWARD), "First table break emits")
	var queue: Array = floor_view.get("_glass").queue
	_check(_kind_count(queue, "extinguisher") == 1, "Table mixes one rare red fragment")
	_check(not emitter.emit(host, "07_table", "break", Vector3.ZERO, Vector3.FORWARD), "Same fact cannot emit twice")
	floor_view.call("clear_glass_debris")
	for index in 5:
		emitter.emit(host, "07_table", "part_%d" % index, Vector3.ZERO, Vector3.FORWARD)
	_check(emitter.get("_events").size() == 4, "A multi-part prop has bounded emission history")
	_check(_kind_count(floor_view.get("_glass").queue, "extinguisher") == 0, "Rare table red fragment is not repeated by every part")
	floor_view.call("clear_glass_debris")
	host.queue_free()


func _test_props() -> void:
	var cases := {"09/09_book_small.glb": "paper", "09/09_file_binder.glb": "paper",
		"04/04_cardboard_boxes_1.glb": "cardboard", "05/05_monitor_destructible.glb": "glass",
		"05/05_wall_TV_destructible.glb": "glass", "09/09_fire_extinguisher.glb": "extinguisher",
		"10/10_armchair_green_destructible.glb": "fabric"}
	for model: String in cases:
		var prop := PROP.instantiate() as RigidBody3D
		prop.set("model_path", "res://models/objects/enviroments/" + model)
		stage.add_child(prop)
		prop.freeze = true
		prop.call("configure_world", effects, null)
		prop.call("configure_glass_debris", floor_view)
		await physics_frame
		await physics_frame
		floor_view.call("clear_glass_debris")
		if cases[model] == "extinguisher":
			prop.call("_on_extinguisher_ruptured", Vector3.UP)
		else:
			prop.call("take_projectile_hit", 400.0, Vector3.UP, Vector3.BACK, Vector3.FORWARD, "GRENADE")
			if prop.get("_damage").transition_pending:
				prop.call("_apply_damage", Vector3.UP, Vector3.FORWARD)
		var queue: Array = floor_view.get("_glass").queue
		_check(_kind_count(queue, cases[model]) > 0, "Actual %s destruction queues %s" % [model, cases[model]])
		_check(queue.size() <= 60, "A real destruction event leaves room in the shared stamp queue")
		if cases[model] == "glass":
			_check(_kind_count(queue, "plastic") > 0, "Broken screen mixes plastic with glass")
			var before := queue.size()
			prop.call("take_projectile_hit", 1.0, Vector3.UP, Vector3.BACK, Vector3.FORWARD, "PISTOL")
			_check(floor_view.get("_glass").queue.size() == before, "Repeated screen hits do not repeat its screen break")
		prop.queue_free()
		await process_frame
		for child in effects.get_children():
			child.queue_free()
		await process_frame
		floor_view.call("clear_glass_debris")


func _test_table() -> void:
	var table := load("res://game/presentation/office_floor/public/props/07_table.tscn").instantiate() as Node3D
	stage.add_child(table)
	table.call("configure_glass_debris", floor_view)
	await physics_frame
	table.call("take_projectile_hit", 1.0, Vector3.UP, Vector3.BACK, Vector3.FORWARD, "PISTOL")
	_check(floor_view.get("_glass").queue.is_empty(), "Undamaged table hit does not emit a fake break")
	table.call("take_projectile_hit", 400.0, Vector3.UP, Vector3.BACK, Vector3.FORWARD, "GRENADE")
	var queue: Array = floor_view.get("_glass").queue
	_check(_kind_count(queue, "wood") > 0 and _kind_count(queue, "paper") > 0, "Real staged table break mixes wood and paper")
	_check(_kind_count(queue, "extinguisher") <= 1, "Table and parts share the rare red fragment guard")
	table.queue_free()
	await process_frame
	floor_view.call("clear_glass_debris")


func _test_legacy_table() -> void:
	var table := load("res://game/presentation/office_floor/public/props/07_table_longest.tscn").instantiate() as Node3D
	stage.add_child(table)
	table.call("configure_world", effects, null)
	table.call("configure_glass_debris", floor_view)
	await physics_frame
	await physics_frame
	var body := table.get_node("Body") as RigidBody3D
	body.freeze = true
	_check(body.get("_floor_debris").floor_view == floor_view, "Legacy root forwards the floor to its body")
	body.call("take_projectile_hit", 10000.0, Vector3(0.7, 0.2, 0.3), Vector3.BACK, Vector3.FORWARD, "GRENADE")
	var queue: Array = floor_view.get("_glass").queue
	_check(_kind_count(queue, "wood") > 0 and _kind_count(queue, "paper") > 0, "Legacy table leg/body destruction emits mixed floor debris")
	_check(_kind_count(queue, "extinguisher") <= 1, "Legacy leg/body also share the rare red guard")
	table.queue_free()
	await process_frame
	for child in effects.get_children():
		child.queue_free()
	await process_frame
	floor_view.call("clear_glass_debris")


func _test_render() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.5
	stage.add_child(camera)
	camera.look_at_from_position(Vector3(0, 8, 0.01), Vector3.ZERO)
	camera.current = true
	var light := DirectionalLight3D.new()
	stage.add_child(light)
	light.rotation_degrees = Vector3(-65, -15, 0)
	await process_frame
	await RenderingServer.frame_post_draw
	var clean := root.get_texture().get_image()
	var kinds := ATLASES.DEFINITIONS.keys()
	for index in kinds.size():
		var at := Vector2((index % 4 - 1.5) * 1.6, (floori(index / 4.0) - 0.5) * 1.6)
		floor_view.call("stamp_material_debris", at, kinds[index], 10, 1.4, index % 4)
	for frame in 16:
		await process_frame
	await RenderingServer.frame_post_draw
	var dirty := root.get_texture().get_image()
	var changed := 0
	for y in range(0, clean.get_height(), 2):
		for x in range(0, clean.get_width(), 2):
			if not clean.get_pixel(x, y).is_equal_approx(dirty.get_pixel(x, y)):
				changed += 1
	_check(changed > 100, "Native floor shader draws mixed debris and surface map")
	_check(not floor_view.is_processing(), "Native mixed bake returns to idle")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		DirAccess.make_dir_recursive_absolute(args[0])
		dirty.save_png(args[0].path_join("material_floor_atlases.png"))
	floor_view.call("clear_glass_debris")
	camera.queue_free()
	light.queue_free()


func _kind_count(queue: Array, kind: String) -> int:
	var count := 0
	for request: Dictionary in queue:
		if request.kind == kind:
			count += 1
	return count


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
