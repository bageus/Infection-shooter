extends SceneTree
## Real atlas pixels, bounded baking, section materials and actual breakable scenes.
const FLOOR := preload("res://game/presentation/office_floor/public/base_floor_renderer.gd")
const BAKE := preload("res://game/presentation/office_floor/glass_floor_bake.gd")
const SCENES := ["glass_wall_full", "glass_partition_half", "glass_partition_blinds", "sliding_glass_door"]
var failures := 0
var stage: Node3D
var floor_view: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_pixels_and_budgets()
	stage = Node3D.new()
	root.add_child(stage)
	floor_view = FLOOR.new()
	stage.add_child(floor_view)
	await _test_sections()
	await _test_breakage()
	if DisplayServer.get_name() != "headless":
		await _test_render()
	stage.queue_free()
	await process_frame
	await process_frame
	print("Glass floor debris tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _test_pixels_and_budgets() -> void:
	var bake := BAKE.new(func(_cell: Vector2i, _texture: Texture2D) -> void: pass)
	bake.prepare()
	var hashes: Dictionary = {}
	for frame in 16:
		bake.clear()
		_check(bake.stamp(Vector2(4, 4), frame, 1.0, frame % 4), "Every atlas frame is accepted")
		bake.step()
		var image: Image = bake.tiles[Vector2i.ZERO].image
		_check(_opaque(image) > 50, "Every atlas frame has visible glass pixels")
		_check(image.get_pixel(0, 0).a == 0.0, "Empty floor remains transparent")
		hashes[hash(image.get_data())] = true
	_check(hashes.size() == 16, "All sixteen cropped atlas frames are distinct")
	bake.clear()
	bake.stamp(Vector2(8, 8), 8, 1.2)
	bake.step()
	_check(bake.tiles.size() == 4, "A corner stamp reaches all four sections")
	for tile: Dictionary in bake.tiles.values():
		_check(_opaque(tile.image) > 0, "No part disappears at a section boundary")
	var previous := bake.uploads
	bake.step()
	_check(bake.uploads - previous <= 1, "No more than one texture upload per step")
	bake.clear()
	for index in 200:
		bake.stamp(Vector2(index * 8 + 4, 4), index % 16, 1.0)
	_check(bake.queue.size() == BAKE.MAX_QUEUE, "A mass break cannot grow the queue indefinitely")
	var timings: Array[int] = []
	var pending := true
	while pending:
		var started := Time.get_ticks_usec()
		pending = bake.step()
		timings.append(Time.get_ticks_usec() - started)
	timings.sort()
	print("Glass bake burst: %d steps; median %.3f ms; peak %.3f ms (%s)" % [timings.size(), timings[timings.size() / 2] / 1000.0, timings[-1] / 1000.0, DisplayServer.get_name()])
	_check(bake.tiles.size() == BAKE.MAX_TILES, "CPU and GPU section counts stay bounded")
	_check(not bake.tiles.has(Vector2i.ZERO), "Old sections are released on overflow")
	previous = bake.uploads
	bake.step()
	_check(previous == bake.uploads, "An idle bake performs no uploads")
	bake.clear()
	for index in 12:
		bake.stamp(Vector2(4, 4), 1, 1.0)
	while bake.step():
		pass
	_check(bake.tiles[Vector2i.ZERO].density[Vector2i(4, 4)] == BAKE.MAX_DENSITY, "Repeated hits cannot build an opaque pile forever")
	_check(not bake.stamp(Vector2(NAN, 0), 0, 1.0), "Invalid coordinates are rejected")
	_check(not bake.stamp(Vector2.ZERO, 16, 1.0) and not bake.stamp(Vector2.ZERO, 0, INF), "Invalid frames and sizes are rejected")
	bake.clear()
	_check(bake.tiles.is_empty() and bake.queue.is_empty(), "Clear releases all transient state")


func _test_sections() -> void:
	var nodes_before := floor_view.get_child_count()
	var originals: Dictionary = {}
	for child: MultiMeshInstance3D in floor_view.get_children():
		originals[child] = child.material_override
	_check(floor_view.call("stamp_glass_debris", Vector2(0, 2), 8, 1.2, 1), "Floor accepts a real stamp")
	for index in 8:
		await process_frame
	_check(floor_view.get_child_count() == nodes_before, "Debris adds no mesh or physics nodes")
	var changed := 0
	for child: MultiMeshInstance3D in floor_view.get_children():
		if child.material_override != originals[child]:
			changed += 1
			_check(child.material_override.get_shader_parameter("glass_enabled"), "Dirty sections read the baked texture")
	_check(changed > 0 and changed <= 8, "Only touched section/material batches change")
	_check(not floor_view.is_processing(), "Floor callbacks stop once the queue is drained")
	floor_view.call("clear_glass_debris")
	for child: MultiMeshInstance3D in floor_view.get_children():
		_check(child.material_override == originals[child], "Clear restores shared clean floor materials")
	floor_view.call("set_stair_openings", [Rect2(-1, -1, 2, 2)] as Array[Rect2])
	_check(not floor_view.call("stamp_glass_debris", Vector2.ZERO, 0, 1.0), "A stair opening receives no stamp")
	_check(not floor_view.call("stamp_glass_debris", Vector2(400, 0), 0, 1.0), "No debris outside the authored floor")
	floor_view.call("set_stair_openings", [] as Array[Rect2])


func _test_breakage() -> void:
	var effects := Node3D.new()
	stage.add_child(effects)
	for index in SCENES.size():
		var scene := load("res://game/presentation/office_floor/public/structural/%s.tscn" % SCENES[index]).instantiate() as Node3D
		stage.add_child(scene)
		scene.position = Vector3(index * 5 - 8, 0, 0)
		if index == 1:
			scene.rotation.y = deg_to_rad(37.0)
		scene.call("configure_world", effects, null)
		scene.call("configure_glass_debris", floor_view)
		await physics_frame
		await physics_frame
		if SCENES[index] == "sliding_glass_door":
			var controller := scene.get_node("DoorController")
			controller.set("_swing_side", 1.0)
			controller.set("_open_amount", 1.0)
			controller.call("_update_door_visuals", Vector3(0, 0, 1))
		var glass := scene.get_node("GlassBody") as StaticBody3D
		_check(glass.get("_debris_floor") == floor_view, "The public scene forwards the real floor to its glass body")
		var center := (glass.get("_glass_nodes")[0] as MeshInstance3D).global_position + Vector3.UP
		glass.call("take_projectile_hit", 30.0, center, Vector3.BACK, Vector3.FORWARD, "PISTOL")
		_check((floor_view.get("_glass") as RefCounted).get("queue").is_empty(), "A crack alone makes no floor debris")
		glass.call("take_projectile_hit", 100.0, center, Vector3.BACK, Vector3.FORWARD, "GRENADE")
		var bake := floor_view.get("_glass") as RefCounted
		var queued: int = bake.get("queue").size()
		_check(queued > 0 and queued <= 12, "Actual pane destruction queues a bounded scatter")
		glass.call("take_projectile_hit", 100.0, center, Vector3.BACK, Vector3.FORWARD, "GRENADE")
		_check(bake.get("queue").size() == queued, "Broken panes never duplicate their scatter")
		for frame in 16:
			await process_frame
		_check(not bake.get("tiles").is_empty(), "Actual pane destruction leaves baked pixels")
		floor_view.call("clear_glass_debris")
		scene.queue_free()
		for child in effects.get_children():
			child.queue_free()
		await process_frame
	# Exterior windows retain their existing unbreakable behavior.
	var exterior := load("res://game/presentation/office_floor/public/structural/window_double.tscn").instantiate() as Node3D
	stage.add_child(exterior)
	exterior.call("configure_world", effects, null)
	exterior.call("configure_glass_debris", floor_view)
	await physics_frame
	await physics_frame
	exterior.get_node("GlassBody").call("take_projectile_hit", 100.0, Vector3.UP, Vector3.BACK, Vector3.FORWARD, "GRENADE")
	_check((floor_view.get("_glass") as RefCounted).get("queue").is_empty(), "Unbreakable exterior windows generate no loose glass")
	exterior.queue_free()
	effects.queue_free()
	await process_frame


func _test_render() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.0
	stage.add_child(camera)
	camera.look_at_from_position(Vector3(0, 8, 0.01), Vector3.ZERO)
	camera.current = true
	var light := DirectionalLight3D.new()
	stage.add_child(light)
	light.rotation_degrees = Vector3(-65, -15, 0)
	await process_frame
	await RenderingServer.frame_post_draw
	var clean := root.get_texture().get_image()
	# Cross both a tile seam and a section boundary.
	floor_view.call("stamp_glass_debris", Vector2(0, 0), 10, 1.5)
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var dirty := root.get_texture().get_image()
	var changed := 0
	var outside := 0
	for y in range(0, clean.get_height(), 2):
		for x in range(0, clean.get_width(), 2):
			if clean.get_pixel(x, y).is_equal_approx(dirty.get_pixel(x, y)):
				continue
			changed += 1
			if Vector2(x, y).distance_to(Vector2(clean.get_size()) * 0.5) > clean.get_width() * 0.25:
				outside += 1
	_check(changed > 50, "Native floor shader visibly draws the glass atlas")
	_check(outside < 10, "Native glass pixels stay local to their footprint")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		DirAccess.make_dir_recursive_absolute(args[0])
		clean.save_png(args[0].path_join("glass_floor_before.png"))
		dirty.save_png(args[0].path_join("glass_floor_after.png"))
	floor_view.call("clear_glass_debris")
	camera.queue_free()
	light.queue_free()


func _opaque(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.02:
				count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
