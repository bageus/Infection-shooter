extends SceneTree
## Real mission with green blood forced (the Yandex build): infected are shot and one is
## blown apart, then the area around the player is captured.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --audio-driver Dummy --script res://tools/capture_green_blood.gd -- <out_dir>
##
## Writes <out_dir>/green_blood_<n>.png.

const MAIN := preload("res://game/bootstrap/app/main.tscn")
const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const BRUTE := preload("res://game/features/infected/public/infected_brute.tscn")
const BLOOD_LEVEL := preload("res://game/core/vfx/public/blood_level.gd")
var _out_dir := "/tmp/green_blood"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out_dir = args[0]
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1000, 600)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	BLOOD_LEVEL.force_green()
	var game := MAIN.instantiate()
	root.add_child(game)
	current_scene = game
	for i in 30:
		await process_frame
	# The mission starts in an unrevealed fog zone; the capture is about blood, not exploration.
	for zone in get_nodes_in_group("darkness_zone"):
		zone.queue_free()
	game.call("set_blood_level", 0, false)
	var player := game.get_node("Gameplay/Player") as Node3D
	player.set("camera_max_distance", 9.0)
	player.set("_camera_distance", 9.0)
	for i in 12:
		await process_frame
	var enemies := game.get("enemies") as Node3D
	var targets: Array[Node3D] = []
	for offset in [Vector3(2.2, 0, 0.5), Vector3(2.0, 0, -1.2), Vector3(3.4, 0, -0.2)]:
		var enemy := (BRUTE if offset.x > 3.0 else HUNGER).instantiate() as Node3D
		enemies.add_child(enemy)
		enemy.global_position = player.global_position + offset + Vector3.UP
		targets.append(enemy)
	for i in 10:
		await process_frame
	for round in 6:
		for enemy in targets:
			if is_instance_valid(enemy):
				var from := enemy.global_position + Vector3(-0.2, 1.1, 0)
				enemy.call("take_projectile_damage", 9.0, from, Vector3(1, 0, 0), "PISTOL")
		await create_timer(0.12).timeout
		if round == 1:
			await _shot(1)
	for enemy in targets:
		if is_instance_valid(enemy):
			enemy.call("take_projectile_damage", 400.0, enemy.global_position + Vector3(0, 1.0, 0), Vector3(1, 0, 0), "SHOTGUN")
	await create_timer(0.35).timeout
	await _shot(2)
	await create_timer(1.8).timeout
	await _shot(3)
	game.free()
	await process_frame
	quit(0)


func _shot(number: int) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out_dir.path_join("green_blood_%d.png" % number))
