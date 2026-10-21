extends SceneTree
## Walking on floor biomass plays its own wet step, not the ordinary or the
## damage sound (ADR-0061).
const PLAYER := preload("res://game/features/player/public/player.tscn")
const BINDINGS := preload("res://game/bootstrap/app/world_bindings.gd")
const DECAL := preload("res://game/presentation/office_floor/public/props/blood_decal.tscn")
const STEP := preload("res://game/presentation/office_floor/public/biomass_footstep_surface.gd")
const SFX := preload("res://game/core/audio/public/sound_events.gd")
var failures := 0
var stage: Node3D
var player: CharacterBody3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
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
	BINDINGS.new(stage, null, player, Callable()).bind_scene(player)
	for tick in 4:
		await physics_frame
		player.velocity = Vector3.DOWN * 4.0
		player.move_and_slide()
	var piece := DECAL.instantiate() as Node3D
	piece.call("configure_blood", "biomass_02", "floor")
	stage.add_child(piece)
	await process_frame
	var solid := _solid_point(piece)
	var driver := player.get_node("AnimationDriver")
	player.global_position = solid + Vector3.UP * 0.9
	driver.emit_signal("footstep", 0, 5.4)
	_check(_voices(&"step_biomass").size() == 1 and _voices(&"step_player").is_empty(), "A step on floor biomass plays the wet step")
	_check(_voices(&"hit_biomass").is_empty(), "It is not the biomass damage sound")
	_clear()
	player.global_position = Vector3(8, 0.9, 8)
	driver.emit_signal("footstep", 1, 5.4)
	_check(_voices(&"step_player").size() == 1 and _voices(&"step_biomass").is_empty(), "Off the biomass the ordinary step returns")
	_clear()
	var paths := {}
	player.global_position = solid + Vector3.UP * 0.9
	for index in 64:
		driver.emit_signal("footstep", index % 2, 5.4)
		for voice in _voices(&"step_biomass"):
			paths[voice.stream.resource_path] = true
		_clear()
	_check(paths.size() == 4, "All four wet recordings are used")
	stage.queue_free()
	await process_frame
	print("Biomass footstep tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


# A world point the public footstep query reports as biomass.
func _solid_point(piece: Node3D) -> Vector3:
	var visual := piece.get_node("BloodQuad") as Node3D
	for vi in range(-45, 46, 3):
		for ui in range(-30, 31, 3):
			var point := visual.to_global(Vector3(ui * 0.01, vi * 0.01, 0.0))
			if STEP.has_biomass_at(stage, point):
				return point
	return Vector3.ZERO


func _voices(event: StringName) -> Array:
	var result := []
	for child in player.get_children():
		if child is AudioStreamPlayer3D and child.is_in_group(StringName("sfx_" + String(event))):
			result.append(child)
	return result


func _clear() -> void:
	for child in player.get_children():
		if child is AudioStreamPlayer3D:
			child.free()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		print("FAIL: ", message)
