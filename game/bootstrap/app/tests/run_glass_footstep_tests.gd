extends SceneTree
## Real ground contacts, bounded raster query, actual shards and roll lifecycle.
const FLOOR := preload("res://game/presentation/office_floor/public/base_floor_renderer.gd")
const PLAYER := preload("res://game/features/player/public/player.tscn")
const GLASS := preload("res://game/presentation/office_floor/public/structural/glass_wall_full.tscn")
const BINDINGS := preload("res://game/bootstrap/app/world_bindings.gd")
var failures := 0
var stage: Node3D
var floor_view: Node3D
var player: CharacterBody3D



func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	floor_view = FLOOR.new()
	floor_view.set("floor_size", Vector2(32, 16))
	stage.add_child(floor_view)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 0.2, 30)
	shape.shape = box
	ground.add_child(shape)
	stage.add_child(ground)
	ground.position.y = -0.1
	player = PLAYER.instantiate()
	player.position.y = 1.0
	stage.add_child(player)
	player.set_physics_process(false)
	player.get_node("AnimationDriver").set_process(false)
	var bindings := BINDINGS.new(stage, null, player, Callable())
	bindings.debris_floor = floor_view
	bindings.bind_scene(player)
	for tick in 4:
		await physics_frame
		player.velocity = Vector3.DOWN * 4.0
		player.move_and_slide()
	_check(player.is_on_floor(), "Real player is grounded")
	_check(not floor_view.call("has_glass_at", Vector3.ZERO), "Clean floor stays quiet")
	var contact := _test_pixels()
	await _test_footsteps(contact)
	await _test_shards()
	await _test_roll()
	floor_view.free()
	player.set("_roll_remaining", 0.0)
	player.get("audio").call("_on_footstep", 0, 5.4)
	_check(_voices(&"step_player").size() == 1, "Freed query collaborator falls back safely")
	stage.queue_free()
	await process_frame
	print("Glass footstep tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _test_pixels() -> Vector3:
	floor_view.call("stamp_glass_debris", Vector2(2, 2), 5, 1.0)
	floor_view.call("_process", 0.0)
	floor_view.set_process(false)
	var bake: RefCounted = floor_view.get("_glass")
	var cell: Vector2i = bake.call("cell_at", Vector2(2, 2))
	var tile: Dictionary = bake.get("tiles")[cell]
	var image := tile.image as Image
	var contact := Vector3.ZERO
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				var at: Vector2 = bake.get("origin") + Vector2(cell) * 8.0 + (Vector2(x, y) + Vector2.ONE * 0.5) / 64.0
				contact = Vector3(at.x, 0, at.y)
				break
		if contact != Vector3.ZERO:
			break
	_check(contact != Vector3.ZERO and floor_view.call("has_glass_at", contact), "Visible glass pixels are audible")
	_check(not floor_view.call("has_glass_at", contact + Vector3.UP), "Glass below another floor stays quiet")
	_check(not floor_view.call("has_glass_at", Vector3(6, 0, 2)), "Nearby clean floor stays quiet")
	floor_view.position = Vector3(3, 0, -4)
	floor_view.rotation.y = PI * 0.5
	_check(floor_view.call("has_glass_at", floor_view.to_global(contact)), "Floor transform is respected")
	floor_view.transform = Transform3D.IDENTITY
	floor_view.call("clear_glass_debris")
	_check(not floor_view.call("has_glass_at", contact), "Clearing pixels removes glass sound")
	floor_view.call("stamp_material_debris", Vector2(contact.x, contact.z), "paper", 0, 1.0)
	floor_view.call("_process", 0.0)
	_check(not floor_view.call("has_glass_at", contact), "Paper is not glass")
	floor_view.call("clear_glass_debris")
	floor_view.call("stamp_glass_debris", Vector2(2, 2), 5, 1.0)
	floor_view.call("_process", 0.0)
	floor_view.set_process(false)
	return contact


func _test_footsteps(contact: Vector3) -> void:
	player.global_position = contact + Vector3.UP * 0.9
	var driver := player.get_node("AnimationDriver")
	driver.emit_signal("footstep", 0, 5.4)
	_check(_voices(&"step_glass").size() == 1 and _voices(&"step_player").is_empty(), "Animation contact selects glass from the feet, not capsule centre")
	_clear_voices()
	var paths: Dictionary = {}
	seed(28173)
	for index in 64:
		driver.emit_signal("footstep", index % 2, 5.4)
		var voices := _voices(&"step_glass")
		if not voices.is_empty():
			paths[voices[0].stream.resource_path] = true
		_clear_voices()
	_check(paths.size() == 4, "Random playback reaches all four owner recordings")
	player.set("_roll_remaining", 0.4)
	driver.emit_signal("footstep", 0, 5.4)
	_check(_voices(&"step_glass").is_empty(), "Roll suppresses walking contacts")
	player.set("_roll_remaining", 0.0)
	player.position = Vector3(6, 0.9, 2)
	driver.emit_signal("footstep", 1, 5.4)
	_check(_voices(&"step_player").size() == 1, "Leaving glass restores ordinary footsteps")
	_clear_voices()
	player.velocity = Vector3.UP * 8.0
	player.move_and_slide()
	await physics_frame
	driver.emit_signal("footstep", 0, 5.4)
	_check(_voices(&"step_player").is_empty() and _voices(&"step_glass").is_empty(), "Airborne contacts stay silent")


func _test_shards() -> void:
	var pane := GLASS.instantiate() as Node3D
	stage.add_child(pane)
	pane.call("configure_world", stage, null)
	pane.get_node("GlassBody").call("take_projectile_hit", 100.0, Vector3.UP, Vector3.BACK, Vector3.FORWARD, "GRENADE")
	var piece: RigidBody3D
	for child in stage.get_children():
		if child is RigidBody3D and bool(child.get_meta(&"glass_debris", false)):
			piece = child
			break
	_check(piece != null, "Actual shattered pane marks physical glass")
	if piece != null:
		piece.freeze = true
		piece.global_position = Vector3(10, 0.08, 0)
		await physics_frame
		await physics_frame
		_check(floor_view.call("has_glass_at", Vector3(10, 0, 0)), "Physical glass works without floor pixels")
		piece.collision_layer = 0
		await physics_frame
		await physics_frame
		_check(not floor_view.call("has_glass_at", Vector3(10, 0, 0)), "Faded shards stop sounding")
	pane.queue_free()


func _test_roll() -> void:
	_clear_voices()
	player.set("_roll_cooldown_remaining", 0.0)
	Input.action_press("move_right")
	Input.action_press("roll")
	await physics_frame
	player.call("_update_move", 0.016)
	player.call("_update_move", 0.016)
	Input.action_release("roll")
	Input.action_release("move_right")
	var voices := _voices(&"player_roll")
	_check(voices.size() == 1, "Accepted roll plays its owner recording exactly once")
	_check(not voices.is_empty() and voices[0].stream is AudioStreamOggVorbis and voices[0].stream.resource_path.ends_with("player_roll/player_roll_1.ogg"), "Roll uses the supplied converted recording")
	_clear_voices()
	player.position = Vector3(6, 0.9, 2)
	player.velocity = Vector3.DOWN
	player.move_and_slide()


func _voices(event: StringName) -> Array[AudioStreamPlayer3D]:
	var result: Array[AudioStreamPlayer3D] = []
	for child in player.get_children():
		if child is AudioStreamPlayer3D and child.is_in_group(StringName("sfx_" + String(event))):
			result.append(child)
	return result


func _clear_voices() -> void:
	for child in player.get_children():
		if child is AudioStreamPlayer3D:
			child.free()


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
