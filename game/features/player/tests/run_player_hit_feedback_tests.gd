extends SceneTree
## Player hit read: a hit flashes the body white (light blue when armor absorbs it)
## and recoils it.

const PLAYER := preload("res://game/features/player/public/player.tscn")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var player := PLAYER.instantiate() as CharacterBody3D
	stage.add_child(player)
	player.set("gravity_acceleration", 0.0)
	await process_frame
	var body := player.get_node("Body")
	var meshes := body.find_children("*", "MeshInstance3D", true, false)
	_expect(not meshes.is_empty(), "The player model has meshes to flash.")

	player.set("armor", 0.0)
	player.call("take_damage", 5.0)
	var overlay := (meshes[0] as MeshInstance3D).material_overlay as StandardMaterial3D
	_expect(overlay != null and overlay.albedo_color.r > 0.95 and overlay.albedo_color.b > 0.95, "An unarmored hit flashes white.")
	await create_timer(0.4).timeout
	_expect((meshes[0] as MeshInstance3D).material_overlay == null, "The flash clears itself.")
	player.set("_iframes_remaining", 0.0)
	player.set("armor", 50.0)
	player.call("take_damage", 5.0)
	overlay = (meshes[0] as MeshInstance3D).material_overlay as StandardMaterial3D
	_expect(overlay != null and overlay.albedo_color.b > overlay.albedo_color.r + 0.3, "An armor-absorbed hit flashes light blue.")
	await create_timer(0.4).timeout

	stage.queue_free()
	await process_frame
	print("Player hit feedback tests, failures: %d" % failures)
	quit(failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)
