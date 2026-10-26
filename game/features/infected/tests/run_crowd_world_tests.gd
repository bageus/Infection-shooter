extends SceneTree
## Separate physics worlds never share neighbours or previous body positions.
const CROWD := preload("res://game/features/infected/crowd_separation.gd")
var failures := 0


func _initialize() -> void: call_deferred("_run")


func _run() -> void:
	await _isolated_worlds()
	await _shared_world()
	await _interleaved_pairs()
	await _world_transfer()
	await _skipped_frames()
	await _world_lifetime()
	print("Crowd world tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _viewport(shared: World3D = null) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = shared == null
	if shared != null: viewport.world_3d = shared
	root.add_child(viewport)
	return viewport


func _body(viewport: SubViewport, position: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	viewport.add_child(body)
	body.position = position
	body.collision_layer = 2
	body.collision_mask = 3
	return body


func _drain() -> void:
	for tick in 3: await physics_frame


func _isolated_worlds() -> void:
	for offset: float in [0.0, 0.2]:
		await _drain()
		var a := _viewport()
		var b := _viewport()
		var first := _body(a, Vector3(1.95, 0, 0))
		var second := _body(b, Vector3(1.95 + offset, 0, 0))
		_check(first.get_world_3d().space != second.get_world_3d().space, "Fixture has independent physics spaces")
		CROWD.spread(first, null)
		await physics_frame
		var push := CROWD.spread(second, null)
		_check(push.is_zero_approx(), "A lone body ignores a different world's previous frame, offset=%s" % offset)
		CROWD.spread(first, null)
		await physics_frame
		_check(CROWD.spread(first, null).is_zero_approx() and CROWD.spread(second, null).is_zero_approx(), "Interleaved independent worlds have no phantom neighbours")
		a.free()
		b.free()


func _shared_world() -> void:
	await _drain()
	var a := _viewport()
	var first := _body(a, Vector3.ZERO)
	var b := _viewport(first.get_world_3d())
	var second := _body(b, Vector3(0.2, 0, 0))
	_check(first.get_world_3d().space == second.get_world_3d().space, "Distinct viewports can intentionally share one world")
	CROWD.spread(first, null)
	CROWD.spread(second, null)
	await physics_frame
	_pair_push(first, second, "shared world across viewports")
	a.free()
	b.free()


func _interleaved_pairs() -> void:
	await _drain()
	var a := _viewport()
	var b := _viewport()
	var first := _body(a, Vector3.ZERO)
	var second := _body(a, Vector3(0.2, 0, 0))
	var other_first := _body(b, Vector3(0.1, 0, 0))
	var other_second := _body(b, Vector3(0.3, 0, 0))
	for body in [first, other_second, second, other_first]: CROWD.spread(body, null)
	await physics_frame
	_pair_push(other_first, other_second, "world B, reversed registration order")
	_pair_push(first, second, "world A, interleaved with B")
	a.free()
	b.free()


func _pair_push(first: CharacterBody3D, second: CharacterBody3D, label: String) -> void:
	var left := CROWD.spread(first, null)
	var right := CROWD.spread(second, null)
	# At 0.2 m spacing and default width 0.7 m, unchanged spacing adds 2.5 * (1 - 2/7).
	_check(left.is_equal_approx(Vector3(-1.7857143, 0, 0)) and right.is_equal_approx(-left), "Existing within-world push remains unchanged: " + label)
	_check(not first.get_collision_mask_value(2) and first.get_collision_mask_value(1) and first.get_collision_layer_value(2), "Spacing changes only the infected mask bit, preserving map/bullet layers")


func _world_transfer() -> void:
	await _drain()
	var a := _viewport()
	var b := _viewport()
	var moved := _body(a, Vector3(50, 0, 0))
	var neighbour := _body(b, Vector3.ZERO)
	CROWD.spread(moved, null)
	CROWD.spread(neighbour, null)
	moved.reparent(b)
	moved.position = Vector3(0.2, 0, 0)
	await physics_frame
	_check(CROWD.spread(moved, null).is_equal_approx(Vector3(1.7857143, 0, 0)), "Transferred body does not reuse its old world's position snapshot")
	a.free()
	b.free()


func _skipped_frames() -> void:
	await _drain()
	var viewport := _viewport()
	var first := _body(viewport, Vector3.ZERO)
	var second := _body(viewport, Vector3(0.2, 0, 0))
	CROWD.spread(first, null)
	CROWD.spread(second, null)
	await _drain()
	_check(CROWD.spread(first, null).is_zero_approx(), "A gap in physics registration discards obsolete neighbours")
	viewport.free()


func _world_lifetime() -> void:
	for cycle in 8:
		await _drain()
		var viewport := _viewport()
		var body := _body(viewport, Vector3.ZERO)
		var world: WeakRef = weakref(body.get_world_3d())
		CROWD.spread(body, null)
		viewport.free()
		await _drain()
		_check(world.get_ref() == null, "Snapshot does not retain a destroyed World3D")
		var replacement := _viewport()
		var lone := _body(replacement, Vector3.ZERO)
		_check(CROWD.spread(lone, null).is_zero_approx(), "New world starts without a destroyed world's neighbours")
		replacement.free()


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
