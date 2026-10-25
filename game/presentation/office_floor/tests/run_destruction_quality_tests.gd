extends SceneTree
## Destruction quality levels: decal budget, pieces staying loose near the player (Medium),
## pieces never baked on a timer (High), baked pieces waking up when the player walks up (Medium).
const QUALITY := preload("res://game/core/vfx/public/destruction_quality.gd")
const FRAGMENT := preload("res://game/presentation/office_floor/environment_fragment.gd")
const RUNTIME := preload("res://game/presentation/office_floor/fragment_runtime.gd")
const BAKE := preload("res://game/presentation/office_floor/glass_floor_bake.gd")
const FLOOR := preload("res://game/presentation/office_floor/public/base_floor_renderer.gd")
const SCATTER := preload("res://game/presentation/office_floor/material_floor_scatter.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_tables()
	_test_bake_budget()
	_test_scatter_volume()
	await _test_loose_pieces()
	await _test_wake_baked()
	await _test_standing_panel()
	await _test_standing_not_baked()
	QUALITY.set_level(QUALITY.DEFAULT)
	print("Destruction quality tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _test_tables() -> void:
	_expect(QUALITY.DEFAULT == QUALITY.MEDIUM and QUALITY.level == QUALITY.MEDIUM, "Medium is the default")
	for table: Array in [QUALITY.QUEUE_MAX, QUALITY.DENSITY_CAP, QUALITY.SPECK_SCALE, QUALITY.SCATTER_PASSES, QUALITY.PIECE_BUDGET, QUALITY.PIECE_BURST]:
		_expect(table.size() == QUALITY.COUNT and table[0] <= table[1] and table[1] <= table[2] and table[0] < table[2], "Each budget grows from Low to High")
	QUALITY.set_level(99)
	_expect(QUALITY.level == QUALITY.HIGH, "Levels are clamped")
	QUALITY.set_level(-4)
	_expect(QUALITY.level == QUALITY.LOW, "Levels are clamped below too")


# A cluster blast asks for hundreds of decals at once; each level must queue and apply a growing share.
func _test_bake_budget() -> void:
	var applied: Array[int] = []
	for level in QUALITY.COUNT:
		QUALITY.set_level(level)
		var bake := BAKE.new(func(_cell: Vector2i, _texture: Texture2D) -> void: pass)
		var queued := 0
		for index in 600:
			queued += int(bake.stamp(Vector2(1.0 + (index % 6) * 0.8, 1.0 + (index / 6 % 6) * 0.8), index % 16, 0.15, 0, "wood"))
		_expect(queued == mini(600, QUALITY.queue_max()), "Level %d queues up to its own limit (%d)" % [level, queued])
		var frames := 0
		while bake.step() and frames < 3000:
			frames += 1
		var total := 0
		for tile: Dictionary in bake.tiles.values():
			for count: int in tile.density.values():
				total += count
		applied.append(total)
	_expect(applied[0] < applied[1] and applied[1] < applied[2], "Decals that reach the floor grow with quality (%s)" % str(applied))


func _test_scatter_volume() -> void:
	var counts: Array[int] = []
	for level in QUALITY.COUNT:
		QUALITY.set_level(level)
		var stage := Node3D.new()
		root.add_child(stage)
		var floor_view := FLOOR.new()
		stage.add_child(floor_view)
		var recipe: Array[String] = ["wood", "wood", "wood", "paper", "plastic", "fabric"]
		SCATTER.scatter(floor_view, Vector3(4, 0, 4), Vector2(2, 1), recipe, Vector3.FORWARD, [] as Array[RID])
		counts.append((floor_view.get("_glass") as RefCounted).get("queue").size())
		stage.free()
	_expect(counts[0] < counts[1] and counts[1] < counts[2], "One broken object leaves more decals at higher quality (%s)" % str(counts))


func _loose_piece(effects: Node3D, at: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.set_script(FRAGMENT)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	body.add_child(mesh)
	effects.add_child(body)
	body.global_position = at
	return body


func _player(effects: Node3D, at: Vector3) -> Node3D:
	var player := Node3D.new()
	player.add_to_group("player")
	effects.add_child(player)
	player.global_position = at
	return player


func _test_loose_pieces() -> void:
	for level in [QUALITY.LOW, QUALITY.MEDIUM, QUALITY.HIGH]:
		QUALITY.set_level(level)
		var effects := Node3D.new()
		root.add_child(effects)
		var runtime := RUNTIME.new()
		runtime.name = "FragmentRuntime"
		effects.add_child(runtime)
		_player(effects, Vector3(20, 0, 0))
		var near := _loose_piece(effects, Vector3(20, 0.2, 2))
		var far := _loose_piece(effects, Vector3(-30, 0.2, 0))
		await process_frame
		await process_frame
		near.set("sleeping", true)
		far.set("sleeping", true)
		near.call("expire")
		far.call("expire")
		await process_frame
		var baked := runtime.get("_baked") as Node
		var count: int = baked.call("count")
		match level:
			QUALITY.LOW:
				_expect(count == 2, "Low bakes every expired piece, near the player or not (%d)" % count)
			QUALITY.MEDIUM:
				_expect(count == 1 and is_instance_valid(near) and not near.is_queued_for_deletion(), "Medium keeps the piece next to the player loose and bakes the far one (%d)" % count)
				near.call("expire_fast")
				await process_frame
				_expect(baked.call("count") == 2, "Medium still bakes a near piece when the budget is full")
			QUALITY.HIGH:
				_expect(count == 0 and is_instance_valid(near) and is_instance_valid(far) and not far.is_queued_for_deletion(), "High keeps both pieces in the scene (%d baked)" % count)
				far.call("expire_fast")
				await process_frame
				_expect(baked.call("count") == 1, "High still bakes a piece when the budget is full, so nothing vanishes")
		effects.queue_free()
		await process_frame


func _test_wake_baked() -> void:
	for level in [QUALITY.LOW, QUALITY.MEDIUM]:
		QUALITY.set_level(level)
		var effects := Node3D.new()
		root.add_child(effects)
		var runtime := RUNTIME.new()
		runtime.name = "FragmentRuntime"
		effects.add_child(runtime)
		var baked := runtime.get("_baked") as Node
		var player := _player(effects, Vector3(-50, 0, 0))
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		effects.add_child(mesh)
		mesh.global_position = Vector3(20, 0.5, 0)
		var distant := MeshInstance3D.new()
		distant.mesh = mesh.mesh
		effects.add_child(distant)
		distant.global_position = Vector3(40, 0.5, 0)
		baked.call("bake", mesh)
		baked.call("bake", distant)
		await create_timer(0.7).timeout
		_expect(baked.call("count") == 2, "Nothing wakes while the player is far away")
		player.global_position = Vector3(21.5, 0, 0)
		await create_timer(1.2).timeout
		var woken := effects.find_children("Fragment_Woken*", "RigidBody3D", false, false)
		if level == QUALITY.LOW:
			_expect(baked.call("count") == 2 and woken.is_empty(), "Low never wakes baked pieces")
		else:
			_expect(baked.call("count") == 1 and woken.size() == 1, "Medium wakes only the baked piece next to the player (%d woken)" % woken.size())
			var body := woken[0] as RigidBody3D
			_expect(body.get_script() == FRAGMENT and body.global_position.distance_to(Vector3(20, 0.5, 0)) < 0.3, "The woken piece is a loose fragment where it was baked")
			body.take_projectile_hit(80.0, body.global_position, Vector3.UP, Vector3.RIGHT, "PISTOL")
			_expect(not body.is_queued_for_deletion(), "A shot only pushes a woken piece")
		effects.queue_free()
		await process_frame


# A big panel left standing on its edge (a cabinet side) falls flat instead of hanging there.
func _test_standing_panel() -> void:
	QUALITY.set_level(QUALITY.MEDIUM)
	var effects := Node3D.new()
	root.add_child(effects)
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	var ground_shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(20, 0.2, 20)
	ground_shape.shape = slab
	ground.add_child(ground_shape)
	ground.position.y = -0.1 + FRAGMENT.FLOOR_TOP
	effects.add_child(ground)
	var runtime := RUNTIME.new()
	runtime.name = "FragmentRuntime"
	effects.add_child(runtime)
	var panel := RigidBody3D.new()
	panel.set_script(FRAGMENT)
	panel.set("blast_motion", true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.05, 1.0, 0.8)
	shape.shape = box
	panel.add_child(shape)
	var mesh := MeshInstance3D.new()
	var visual := BoxMesh.new()
	visual.size = box.size
	mesh.mesh = visual
	panel.add_child(mesh)
	effects.add_child(panel)
	panel.global_position = Vector3(0, 0.52, 0)
	await create_timer(0.6).timeout
	panel.sleeping = true
	await create_timer(1.6).timeout
	var lying := panel.is_queued_for_deletion() or absf(panel.global_basis.x.y) > 0.8
	_expect(lying or runtime.get("_baked").count() > 0, "A panel standing on its edge is pushed over instead of freezing upright")
	effects.queue_free()
	await process_frame


# A big piece still standing when its time is up (a divider panel after a blast) must not be baked into
# the floor as a fake frame; a big piece lying flat is baked, and a full budget removes a standing one.
func _test_standing_not_baked() -> void:
	QUALITY.set_level(QUALITY.LOW)
	var effects := Node3D.new()
	root.add_child(effects)
	var runtime := RUNTIME.new()
	runtime.name = "FragmentRuntime"
	effects.add_child(runtime)
	var standing := _frozen_panel(effects, Basis.IDENTITY, Vector3(0, 0.52, 0))
	var lying := _frozen_panel(effects, Basis(Vector3.BACK, PI / 2.0), Vector3(3, 0.03, 0))
	var leaning := _frozen_panel(effects, Basis(Vector3.BACK, deg_to_rad(40.0)), Vector3(6, 0.5, 0))
	await process_frame
	standing.expire()
	leaning.expire_fast()
	_expect(runtime.get("_baked").count() == 0, "A standing or leaning big piece is not baked")
	_expect(is_instance_valid(standing) and not standing.is_queued_for_deletion() and not standing.has_meta("debris_fading"), "An unforced standing piece stays a loose body")
	_expect(is_instance_valid(leaning) and not leaning.has_meta("debris_fading"), "A standing piece the budget asks for does not vanish while the debris is under the burst limit")
	lying.expire()
	_expect(runtime.get("_baked").count() == 1, "A big piece lying flat is baked")
	effects.queue_free()
	await process_frame


func _frozen_panel(parent: Node3D, orientation: Basis, at: Vector3) -> RigidBody3D:
	var panel := RigidBody3D.new()
	panel.set_script(FRAGMENT)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.05, 1.0, 0.8)
	shape.shape = box
	panel.add_child(shape)
	var mesh := MeshInstance3D.new()
	var visual := BoxMesh.new()
	visual.size = box.size
	mesh.mesh = visual
	panel.add_child(mesh)
	parent.add_child(panel)
	panel.freeze = true
	panel.global_transform = Transform3D(orientation, at)
	return panel


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
	else:
		print("PASS: " + message)
