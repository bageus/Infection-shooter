extends SceneTree

const SURFACES := preload("res://game/presentation/office_floor/blood_surface_query.gd")
const EFFECTS := preload("res://game/presentation/office_floor/public/blood_effects_3d.tscn")
const LIBRARY := preload("res://game/presentation/office_floor/blood_texture_library.gd")
const STAMP := preload("res://game/presentation/office_floor/blood_floor_stamp.gd")
var failures := 0
var stage: Node3D
var camera: Camera3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	_add_body(Vector3(0, -0.1, 0), Vector3(200, 0.2, 200))
	var wall := _add_body(Vector3(0, 2, -3), Vector3(20, 4, 0.2))
	camera = Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0, 1.5, 0)
	camera.look_at(Vector3(0, 0, -1))
	camera.make_current()
	var query := SURFACES.new()
	stage.add_child(query)
	var texture := _texture()
	var effects := _effects(texture)
	var budget := effects.get("_budget") as Node3D
	budget.get("settings")["decal"] = true
	var bake := budget.get("_floor_bake") as Node3D
	var floor_surface := SURFACES.capture(Vector3(1, 0, -1), Vector3.UP, stage.get_child(0) as Node3D)
	var definition := _definition(texture, Basis.IDENTITY)

	# (a) stamping changes pixels and creates exactly one Decal.
	bake.call("stamp", texture, Color.WHITE, Vector2(0.8, 0.4), Vector3(1, 0, -1), Basis.IDENTITY)
	await create_timer(0.5).timeout
	var tile := bake.call("tile_image", Vector2i(0, -1)) as Image
	_expect(tile != null and _opaque_pixels(tile) > 20, "Stamping writes pixels into the tile")
	_expect(_count(bake, "Decal") == 1 and bake.get_child_count() == 2, "One tile shows exactly one Decal")
	_expect(((_first(bake, "Decal") as Decal).cull_mask == 128) and (_first(bake, "Decal") as Decal).size == Vector3(4, 0.5, 4), "Decal uses the receiver mask and 4 m size")
	bake.call("clear")

	# (b) a floor mark evicted by the budget is baked and its node is freed.
	budget.set("max_marks", 1)
	budget.call("submit", definition, floor_surface)
	await create_timer(0.3).timeout
	_expect(budget.call("statistics")["marks"] == 1, "The first floor mark is drawn")
	budget.call("submit", _definition(texture, Basis.IDENTITY), SURFACES.capture(Vector3(-1, 0, -1), Vector3.UP, stage.get_child(0) as Node3D))
	await create_timer(2.5).timeout
	var stats: Dictionary = budget.call("statistics")
	_expect(stats["baked"]["tiles"] >= 1 and _opaque_pixels(bake.call("tile_image", Vector2i(-1, -1)) if bake.call("tile_image", Vector2i(-1, -1)) != null else bake.call("tile_image", Vector2i(0, -1))) > 0, "An evicted floor mark leaves a baked tile")
	_expect((budget.get("container") as Node3D).get_child_count() == 1, "The evicted mark node is freed")
	budget.call("clear_marks")

	# (c) the live tile count never exceeds the cap.
	for index in 30:
		bake.call("stamp", texture, Color.WHITE, Vector2(0.6, 0.3), Vector3(index * 4.0 + 1.0, 0, 1.0), Basis.IDENTITY)
	var peak := 0
	for step in 40:
		await create_timer(0.1).timeout
		peak = maxi(peak, bake.call("statistics")["live"])
		_expect(_count(bake, "Decal") <= 17, "Decal nodes stay near the cap")
	_expect(peak == 16 and bake.call("statistics")["live"] == 16 and bake.call("statistics")["tiles"] == 30, "Live tiles are capped at 16 with the rest kept as data")

	# (d) clear_marks removes tiles and decals.
	budget.call("clear_marks")
	await create_timer(0.3).timeout
	_expect(bake.call("statistics")["tiles"] == 0 and _count(bake, "Decal") == 0, "clear_marks removes tiles and Decals")

	# (e) a wall mark is not baked.
	budget.set("max_marks", 1)
	var wall_basis := SURFACES.surface_basis(Vector3.BACK, Vector3.UP, true, 0.0)
	var wall_surface := SURFACES.capture(Vector3(0, 1.5, -2.9), Vector3.BACK, wall)
	budget.call("submit", _definition(texture, wall_basis), wall_surface)
	await create_timer(0.3).timeout
	budget.call("submit", _definition(texture, wall_basis), SURFACES.capture(Vector3(1, 1.5, -2.9), Vector3.BACK, wall))
	await create_timer(2.5).timeout
	_expect(bake.call("statistics")["tiles"] == 0, "A wall mark is not baked")
	budget.call("clear_marks")

	# Quad fallback (no Decal support) still shows one node per tile.
	budget.get("settings")["decal"] = false
	bake.call("stamp", texture, Color.WHITE, Vector2(0.8, 0.4), Vector3(1, 0, -1), Basis.IDENTITY)
	await create_timer(0.5).timeout
	_expect(_count(bake, "MeshInstance3D") == 1, "The quad fallback shows one mesh per tile")
	budget.call("clear_marks")
	print("Blood floor bake tests: %d failures" % failures)
	var nan_cells: Array[Vector2i] = STAMP.cells_touched(Vector3(NAN, 0.0, 0.0), Basis.IDENTITY, Vector2.ONE * 0.5)
	_expect(nan_cells.is_empty(), "A non-finite stain position touches no tiles")
	var huge_cells: Array[Vector2i] = STAMP.cells_touched(Vector3(1.0e9, 0.0, 0.0), Basis.IDENTITY, Vector2.ONE * 0.5)
	_expect(huge_cells.is_empty() or huge_cells.size() <= 4, "An absurd position is clamped, never a large cell list")
	var wide_cells: Array[Vector2i] = STAMP.cells_touched(Vector3.ZERO, Basis.IDENTITY, Vector2(50.0, 0.5))
	_expect(wide_cells.is_empty(), "A stain wider than the span limit touches no tiles")
	quit(0 if failures == 0 else 1)


func _add_body(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 128
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	stage.add_child(body)
	body.position = position
	return body


func _texture() -> ImageTexture:
	var image := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.5, 0.02, 0.01, 0.8))
	return ImageTexture.create_from_image(image)


func _effects(texture: Texture2D) -> Node3D:
	var effects := EFFECTS.instantiate() as Node3D
	effects.set("preload_textures", false)
	var entries: Dictionary = {}
	for category in LIBRARY.CATEGORIES:
		entries[category] = [{"texture": texture, "aspect": 2.0, "variant": 1}]
	(effects.get("_library") as RefCounted).set("entries", entries)
	stage.add_child(effects)
	effects.call("configure_environment", [stage] as Array[Node])
	return effects


func _definition(texture: Texture2D, basis: Basis) -> Dictionary:
	return {"texture": texture, "tint": Color.WHITE, "footprint": Vector2(0.6, 0.3), "basis": basis}


func _opaque_pixels(image: Image) -> int:
	var total := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.1:
				total += 1
	return total


func _count(node: Node, type: String) -> int:
	var total := 0
	for child in node.get_children():
		if child.is_class(type) and not child.is_queued_for_deletion():
			total += 1
	return total


func _first(node: Node, type: String) -> Node:
	for child in node.get_children():
		if child.is_class(type):
			return child
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
