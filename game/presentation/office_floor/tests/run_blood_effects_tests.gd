extends SceneTree

const SURFACES := preload("res://game/presentation/office_floor/blood_surface_query.gd")
const LIBRARY := preload("res://game/presentation/office_floor/blood_texture_library.gd")
const EFFECTS := preload("res://game/presentation/office_floor/public/blood_effects_3d.tscn")
const IMPACTS := preload("res://game/features/combat/public/impact_effects.gd")
const MARK := preload("res://game/presentation/office_floor/blood_mark_3d.gd")
var failures := 0
var stage: Node3D
var query: Node3D
var effects: Node3D
var texture: Texture2D
var excluded: Array[RID] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_basis_and_variants()
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	query = SURFACES.new()
	stage.add_child(query)
	var floor_body := _surface(Vector3.ZERO, Vector3(40, 0.2, 40))
	floor_body.position.y = -0.1
	var wall := _surface(Vector3(0, 1.5, -2), Vector3(4, 3, 0.2))
	var slope := _surface(Vector3(5, 0.4, 0), Vector3(3, 0.2, 3))
	slope.rotation.z = 0.35
	var platform := _surface(Vector3(10, 0.5, 0), Vector3(3, 0.2, 3))
	var actor := CharacterBody3D.new()
	actor.position = Vector3(0, 1, 0)
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	actor.add_child(shape)
	stage.add_child(actor)
	query.call("watch_environment", stage)
	await physics_frame
	await physics_frame
	_expect(actor.collision_layer & 128 == 0, "Actor is excluded from the surface layer.")
	var floor_hit: Dictionary = query.call("find_floor", Vector3(0, 1, 0), excluded)
	_expect(SURFACES.resolve(floor_hit).get("collider") == floor_body, "Down ray finds floor rather than the actor.")
	var wall_hit: Dictionary = query.call("find_behind", Vector3(0, 1, 0), Vector3.FORWARD, excluded)
	_expect(SURFACES.resolve(wall_hit).get("collider") == wall, "Projectile ray finds the wall behind the hit.")
	var slope_hit: Dictionary = query.call("find_floor", Vector3(5, 2, 0), excluded)
	_expect(SURFACES.resolve(slope_hit)["normal"].dot(slope.global_basis.y) > 0.99, "Slope normal matches its receiving surface.")
	var none: Dictionary = query.call("find_floor", Vector3(100, 1, 100), excluded)
	_expect(none.is_empty(), "An absent surface does not produce an airborne mark.")
	_setup_effects()
	var surface_roots: Array[Node] = [stage]
	effects.call("configure_environment", surface_roots)
	_expect(effects.call("diagnostics")["api_valid"], "Running engine supplies every required blood rendering/query API.")
	effects.call("small_stain", Vector3(0, 1, 0), excluded)
	await physics_frame
	await physics_frame
	var marks := _marks()
	_expect(marks.size() == 1, "Small stain produces one bounded mark.")
	if not marks.is_empty():
		var visual := marks[0].get_child(0) as MeshInstance3D
		if visual != null:
			var material := visual.mesh.surface_get_material(0) as StandardMaterial3D
			_expect(not material.emission_enabled and material.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED, "Compatibility blood neither glows nor faces the camera.")
			_expect(visual.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Blood planes cast no shadows.")
		_expect(marks[0].find_children("*", "CollisionObject3D", true, false).is_empty(), "Marks have no physical bodies.")
	effects.call("clear_marks")
	effects.call("small_stain", Vector3(10, 1.5, 0), excluded)
	await physics_frame
	await physics_frame
	marks = _marks()
	if not marks.is_empty():
		var mark := marks[0] as Node3D
		var before := platform.to_local(mark.global_position)
		platform.position += Vector3(0.7, 0.0, 0.0)
		await physics_frame
		await physics_frame
		_expect(platform.to_local(mark.global_position).distance_to(before) < 0.001, "A moving platform retains the mark in local coordinates.")
	effects.call("clear_marks")
	var actor_exclusion: Array[RID] = [actor.get_rid()]
	effects.call("death_pool", Vector3(0, 1, 0), actor_exclusion, 101)
	effects.call("death_pool", Vector3(0, 1, 0), actor_exclusion, 101)
	actor.queue_free()
	await create_timer(0.25).timeout
	_expect(_stats()["pending_pools"] == 1, "Duplicate death schedules only one pool after the actor is removed.")
	await create_timer(0.4).timeout
	_expect(_stats()["marks"] == 1, "A delayed pool survives deletion of its enemy.")
	effects.call("clear_marks")
	var budget := effects.get("_budget") as Node3D
	budget.set("max_marks", 3)
	budget.set("per_surface_limit", 2)
	_expect((budget.get("_timer") as Timer).is_stopped(), "Empty blood budget does not tick")
	for i in range(20):
		effects.call("small_stain", Vector3(i * 0.01, 1, 0), excluded)
	await create_timer(0.6).timeout
	_expect(_stats()["marks"] <= 2 and _stats()["pending"] <= 16, "Local density and global budget include fading marks.")
	effects.call("clear_marks")
	_expect(_stats()["marks"] == 0 and _stats()["pending"] == 0, "Clear removes all marks and pending work.")
	_expect((budget.get("_timer") as Timer).is_stopped(), "Clear stops blood maintenance")
	_expect(budget.get("_surfaces").is_empty() and budget.get("_fading") == 0 and budget.get("_active").first == -1, "Clear releases counters and FIFO")
	await _test_budget_index()
	_test_empty_pool_clear(floor_hit)
	await _test_hit_throttle_and_expiry()
	await _test_decal_growth(floor_hit)
	await _test_proxy_projection()
	await _test_side_splatter()
	stage.queue_free()
	print("Blood effects tests: %d failure(s)." % failures)
	quit(failures)


func _test_hit_throttle_and_expiry() -> void:
	var budget := effects.get("_budget") as Node3D
	budget.set("lifetime", 0.2)
	effects.call("splatter_hit", Vector3(0, 1, 0), Vector3.FORWARD, "UZI", excluded, 500)
	await physics_frame
	await physics_frame
	var single := _stats()["marks"] as int
	effects.call("clear_marks")
	for i in range(12):
		effects.call("splatter_hit", Vector3(0, 1, 0), Vector3.FORWARD, "UZI", excluded, 501)
	await physics_frame
	await physics_frame
	_expect(single >= 1 and _stats()["marks"] == single, "Automatic hits in one interval produce a single burst of splatters.")
	await create_timer(0.5).timeout
	_expect(_stats()["marks"] == 0, "Expired marks finish fading and release their budget.")
	budget.set("lifetime", 30.0)


func _test_side_splatter() -> void:
	# Shot goes straight back (+Z), so only the side rays can reach these columns.
	effects.call("clear_marks")
	(effects.get("_budget") as Node3D).set("max_marks", 20)
	var right := _surface(Vector3(0.8, 1.5, 0), Vector3(0.2, 3, 2))
	var left := _surface(Vector3(-0.8, 1.5, 0), Vector3(0.2, 3, 2))
	query.call("watch_environment", stage)
	await physics_frame
	await physics_frame
	effects.call("splatter_hit", Vector3(0, 1, 0), Vector3.BACK, "UZI", excluded, 601)
	await physics_frame
	await physics_frame
	var marks := _marks()
	var on_right := false
	var on_left := false
	for mark in marks:
		var x := (mark as Node3D).global_position.x
		on_right = on_right or (x > 0.5 and x < 0.9)
		on_left = on_left or (x < -0.5 and x > -0.9)
	_expect(on_right and on_left, "Blood sprays onto the walls and columns beside a hit.")
	effects.call("clear_marks")
	effects.call("splatter_hit", Vector3(0, 1, 0), Vector3.ZERO, "UZI", excluded, 602)
	await physics_frame
	await physics_frame
	_expect(_stats()["marks"] == 1, "A hit without a direction does not fan out sideways.")
	effects.call("clear_marks")
	right.queue_free()
	left.queue_free()
	await physics_frame


func _test_basis_and_variants() -> void:
	for normal in [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3(0, 1, 1).normalized()]:
		for axis_x in [true, false]:
			var basis := SURFACES.surface_basis(normal, normal, axis_x, 0.07)
			_expect(basis.y.dot(normal) > 0.999 and absf(basis.determinant() - 1.0) < 0.001, "Decal +Y matches normal with an orthonormal right-handed basis.")
	var library := LIBRARY.new()
	library.entries["stain"] = [{"variant": 1}, {"variant": 2}, {"variant": 3}, {"variant": 4}]
	var recent: Array = []
	for i in range(40):
		var variant: int = library.choose("stain")["variant"]
		_expect(not recent.has(variant), "Texture selection avoids the previous two variants.")
		recent.append(variant)
		if recent.size() > 2: recent.pop_front()


func _surface(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	stage.add_child(body)
	body.position = position
	return body


func _setup_effects() -> void:
	var image := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	image.set_pixel(8, 4, Color(0.5, 0.02, 0.01, 0.8))
	texture = ImageTexture.create_from_image(image)
	effects = EFFECTS.instantiate() as Node3D
	effects.set("preload_textures", false)
	effects.set("splatters_per_hit", 1)
	effects.set("mark_lifetime", 30.0)
	effects.set("fade_seconds", 0.05)
	effects.set("pool_delay", Vector2(0.4, 0.4))
	effects.set("pool_growth", Vector2(0.2, 0.2))
	stage.add_child(effects)
	var library: RefCounted = effects.get("_library")
	var entries: Dictionary = {}
	for category in LIBRARY.CATEGORIES:
		entries[category] = [{"texture": texture, "aspect": 2.0, "variant": 1}]
	library.set("entries", entries)


func _marks() -> Array[Node]:
	var budget := effects.get("_budget") as Node3D
	var container := budget.get("container") as Node3D
	return container.get_children()


func _stats() -> Dictionary:
	return effects.call("statistics")


func _test_decal_growth(surface: Dictionary) -> void:
	var hit := SURFACES.resolve(surface)
	var mark := MARK.new() as Node3D
	stage.add_child(mark)
	var basis := SURFACES.surface_basis(hit["normal"], Vector3.RIGHT, true, 0.0)
	var definition := {"texture": texture, "footprint": Vector2(0.8, 0.4), "basis": basis, "tint": Color.WHITE, "pool": true, "growth_seconds": 0.2}
	var settings := {"depth": 0.08, "decal": true, "visual_mask": 128, "distance_fade": true, "fade_begin": 24.0, "fade_length": 12.0, "growth_seconds": 0.2}
	mark.call("configure", hit, definition, settings)
	var decal := mark.get_child(0) as Decal
	_expect(decal.texture_emission == null and decal.cull_mask == 128, "Decal has no emission and uses the receiver visual layer.")
	var depth := decal.size.y
	await create_timer(0.3).timeout
	_expect(is_equal_approx(decal.size.y, depth) and is_equal_approx(decal.size.x, 0.8), "Pool grows only in X/Z; projection depth remains fixed.")
	mark.queue_free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _test_budget_index() -> void:
	var budget := effects.get("_budget") as Node3D
	budget.set("max_marks", 3)
	budget.set("per_surface_limit", 0)
	for i in 3:
		effects.call("small_stain", Vector3(i, 1, 0), excluded)
	await physics_frame
	await physics_frame
	var records: Dictionary = budget.get("_records")
	var ids := records.keys()
	_expect(ids.size() == 3, "Three marks enter global FIFO")
	if ids.size() == 3:
		var key: int = records[ids[0]]["key"]
		var counts: Dictionary = budget.get("_surfaces")
		_expect(counts[key]["count"] == 3, "Surface counter includes every mark")
		budget.call("_retire", ids[1])
		_expect(budget.get("_active").first == ids[0], "Retiring middle mark preserves oldest active")
		budget.call("_remove", ids[0])
		_expect(budget.get("_active").first == ids[2], "Deleting oldest advances FIFO")
		_expect(counts[key]["count"] == 2 and counts[key]["fading"] == 1 and budget.get("_fading") == 1, "Fading continues to consume density budget")
	effects.call("clear_marks")
	await process_frame

func _test_empty_pool_clear(surface: Dictionary) -> void:
	var budget := effects.get("_budget") as Node3D
	var definition := {"texture": texture, "basis": Basis.IDENTITY, "footprint": Vector2.ONE, "tint": Color.RED}
	budget.call("schedule_pool", 991, definition, surface, 5.0)
	_expect(not (budget.get("_timer") as Timer).is_stopped(), "Delayed pool wakes empty budget")
	budget.call("clear_marks")
	_expect((budget.get("_timer") as Timer).is_stopped(), "Clearing only delayed requests stops timer immediately")


func _test_proxy_projection() -> void:
	var pool := IMPACTS.new() as Node3D
	stage.add_child(pool)
	effects.call("configure_world", stage, pool)
	var budget := effects.get("_budget") as Node3D
	budget.get("settings")["decal"] = false
	budget.set("lifetime", 30.0)
	var body := _surface(Vector3(20, 0.5, 0), Vector3(2, 1, 2))
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = Vector3(2, 0.6, 2)
	mesh.position.y = -.2 # Visual top .6, proxy top 1.0: outside projection depth.
	body.add_child(mesh)
	query.call("watch_environment", body)
	query.set("projection_pool", weakref(pool))
	await physics_frame
	await physics_frame
	var surface: Dictionary = query.call("find_floor", Vector3(20, 2, 0), excluded)
	var hit := SURFACES.resolve(surface)
	_expect(is_equal_approx(float(hit["position"].y), .6), "Blood ray refines proxy hit onto visible model")
	var definition := {"texture": texture, "basis": Basis.IDENTITY, "footprint": Vector2.ONE, "tint": Color.RED}
	budget.call("submit", definition, surface)
	_expect(_stats()["marks"] == 1 and not (_marks()[0].get("_projected") as Array).is_empty(), "Refined proxy receives a textured mesh projection")
	effects.call("clear_marks")
	# A surface outside every receiver produces no phantom node, FIFO or counter.
	var unsupported := SURFACES.capture(Vector3(20, 3, 0), Vector3.UP, body)
	budget.call("submit", definition, unsupported)
	_expect(_stats()["marks"] == 0 and _marks().is_empty(), "Unsupported projection consumes no mark budget")
	_expect(budget.get("_surfaces").is_empty() and budget.get("_active").first == -1, "Unsupported projection leaves no surface or FIFO record")
	query.set("projection_pool", null)
	effects.call("configure_world", stage, null)
	body.queue_free()
	pool.queue_free()
	await process_frame
