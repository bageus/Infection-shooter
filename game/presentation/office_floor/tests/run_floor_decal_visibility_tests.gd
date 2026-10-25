extends SceneTree
## Actual floor pixels, destruction spread and confirmed foot contacts at normal sizes.
const FLOOR := preload("res://game/presentation/office_floor/public/base_floor_renderer.gd")
const IMPACTS := preload("res://game/features/combat/public/impact_effects.gd")
var failures := 0
var stage: Node3D
var floor_view: Node3D

class ObservedFloor extends FLOOR:
	var accepted: Array[Vector2] = []
	var scuffs := 0
	func stamp_material_debris(at: Vector2, kind: String, frame: int, size: float, turns: int = 0, min_size: float = 0.1) -> bool:
		var ok := super.stamp_material_debris(at, kind, frame, size, turns, min_size)
		if ok: accepted.append(at)
		return ok
	func stamp_floor_surface(at: Vector2, kind: String, frame: int, size: float, turns: int = 0) -> bool:
		var ok := super.stamp_floor_surface(at, kind, frame, size, turns)
		if ok and kind == "floor_scuff": scuffs += 1
		return ok


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	floor_view = ObservedFloor.new()
	floor_view.floor_size = Vector2(16, 16)
	stage.add_child(floor_view)
	_test_scatter()
	_test_scuff_pixels()
	await _test_foot_contacts()
	if DisplayServer.get_name() != "headless": await _test_native_pixels()
	stage.free()
	await process_frame
	print("Floor decal visibility tests: %d failure(s)." % failures)
	quit(failures)


func _drain() -> void:
	while floor_view._glass.step(): pass
	floor_view._process(0)


func _test_scatter() -> void:
	for kind: String in ["wood", "plastic", "fabric"]:
		floor_view.clear_glass_debris()
		floor_view.accepted.clear()
		seed(322)
		var recipe: Array[String] = [kind, kind, kind, kind, kind, kind]
		floor_view.scatter_prop_debris(Vector3.ZERO, Vector2(4, 4), recipe, Vector3.FORWARD)
		var outside := 0
		for point: Vector2 in floor_view.accepted:
			outside += int(absf(point.x) > 2 or absf(point.y) > 2)
		print("DEBRIS_VISIBLE_SPREAD ", kind, " outside=", outside, " accepted=", floor_view.accepted.size())
		_check(floor_view.accepted.size() > 6 and outside >= floor_view.accepted.size() * .75, kind + " mostly lands outside the source footprint")
		var nodes := floor_view.get_child_count()
		_drain()
		var alpha := 0.0
		for tile: Dictionary in floor_view._glass.tiles.values():
			alpha += _peak(tile.image)
		_check(alpha > .5, kind + " leaves visible color pixels on the actual floor")
		_check(floor_view.get_child_count() == nodes and not floor_view.is_processing(), "Decals use existing floor batches and return to idle")


func _test_scuff_pixels() -> void:
	floor_view.clear_glass_debris()
	var minimum := 1.0
	for frame in 16:
		floor_view.clear_glass_debris()
		floor_view.stamp_floor_surface(Vector2.ZERO, "floor_scuff", frame, .35)
		_drain()
		var peak := 0.0
		for tile: Dictionary in floor_view._glass.tiles.values():
			if tile.layers.has(1): peak = maxf(peak, _peak(tile.layers[1].image))
		minimum = minf(minimum, peak)
		_check(peak >= .04 and peak <= .19, "Small default scuff is readable but remains subtle, frame%d alpha%.3f" % [frame, peak])
	print("SCUFF_MINIMUM_PEAK ", minimum)
	floor_view.configure_surface_decals({"floor_scuff": {"opacity": 0.0}})
	_check(not floor_view.stamp_floor_surface(Vector2.ZERO, "floor_scuff", 0, .5), "Zero opacity still suppresses scuffs")
	floor_view.configure_surface_decals({})


func _test_foot_contacts() -> void:
	floor_view.clear_glass_debris()
	floor_view.scuffs = 0
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(16, .2, 16)
	shape.shape = box
	ground.add_child(shape)
	ground.position.y = -.0865
	stage.add_child(ground)
	var actor := CharacterBody3D.new()
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = .3
	collision.shape = capsule
	actor.add_child(collision)
	stage.add_child(actor)
	actor.position = Vector3(-6, 1, 0)
	var impacts := IMPACTS.new()
	stage.add_child(impacts)
	impacts.surface_step = Callable(floor_view, "bake_step")
	for tick in 8:
		await physics_frame
		actor.velocity = Vector3.DOWN * 4
		actor.move_and_slide()
	_check(actor.is_on_floor(), "Test contact uses a genuinely grounded body")
	seed(109)
	for step in 120:
		await physics_frame
		actor.position.x = -6 + step * .1
		actor.velocity = Vector3.DOWN * 4
		actor.move_and_slide()
		impacts.request_surface_step(actor)
	print("CONFIRMED_FOOT_SCUFFS ", floor_view.scuffs)
	_check(floor_view.scuffs >= 20, "Normal walking creates occasional scuffs without requiring hundreds of steps")
	_drain()
	var before: int = floor_view.scuffs
	actor.position.y = 3
	actor.velocity = Vector3.UP
	actor.move_and_slide()
	impacts.request_surface_step(actor)
	_check(floor_view.scuffs == before, "Airborne movement cannot scratch the floor")


func _test_native_pixels() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6
	stage.add_child(camera)
	camera.look_at_from_position(Vector3(0, 8, .01), Vector3.ZERO)
	camera.current = true
	var light := DirectionalLight3D.new()
	stage.add_child(light)
	light.rotation_degrees = Vector3(-65, -15, 0)
	for kind: String in ["wood", "plastic", "fabric", "floor_scuff"]:
		floor_view.clear_glass_debris()
		for tick in 4: await process_frame
		await RenderingServer.frame_post_draw
		var clean := root.get_texture().get_image()
		if kind == "floor_scuff":
			floor_view.stamp_floor_surface(Vector2.ZERO, kind, 0, .6)
		else:
			seed(322)
			var recipe: Array[String] = [kind, kind, kind, kind, kind, kind]
			floor_view.scatter_prop_debris(Vector3.ZERO, Vector2(4, 4), recipe, Vector3.FORWARD)
		for tick in 24: await process_frame
		await RenderingServer.frame_post_draw
		var dirty := root.get_texture().get_image()
		var changed := 0
		for y in range(0, clean.get_height(), 2):
			for x in range(0, clean.get_width(), 2):
				if not clean.get_pixel(x, y).is_equal_approx(dirty.get_pixel(x, y)): changed += 1
		print("NATIVE_FLOOR_DECAL ", kind, " changed_pixels=", changed)
		_check(changed > 4, "Actual small-size floor shader pixels remain visible: " + kind)


func _peak(image: Image) -> float:
	var bytes := image.get_data()
	var peak := 0
	for index in range(3, bytes.size(), 4): peak = maxi(peak, bytes[index])
	return float(peak) / 255.0


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
