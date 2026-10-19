extends SceneTree
## Captures the antidote frame sequence after the second control loss (two passes):
## the frame snapping from the screen edges onto the syringe cell, its hold, and the fade.
## Run under xvfb with a real renderer: ... --script tools/capture_antidote_hint.gd -- <output dir>

const HUD := preload("res://game/presentation/prototype_hud/public/prototype_hud.tscn")
const PLAYER := preload("res://game/features/player/public/player.tscn")
# Seconds after the loss starts; covers both passes of the second loss.
const SHOT_TIMES := [0.1, 0.3, 0.9, 2.0, 3.2, 3.9, 4.2, 4.6, 5.2, 6.5, 7.6]

var _shots := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out_dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://antidote_hint"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var player := PLAYER.instantiate() as Node3D
	player.name = "Player"
	stage.add_child(player)
	player.set("antidotes", 4)
	var hud := HUD.instantiate()
	hud.set("player_path", NodePath("../Player"))
	stage.add_child(hud)
	var runtime := player.get_node("InfectionRuntime")
	await _frames(3)

	# First loss, then recover and cross again: the second loss plays two passes.
	runtime.call("absorb_mutagen", 6.2)
	await _frames(5)
	await _wait_until_control_returns(runtime)
	await _restore_mutation(runtime)
	await _frames(30)
	runtime.call("absorb_mutagen", 6.2)
	var elapsed := 0.0
	for time in SHOT_TIMES:
		await create_timer(time - elapsed).timeout
		elapsed = time
		var frame: Control = hud.get("_antidote_hint")
		print("t=%.2f frame visible=%s pos=%s size=%s alpha=%.2f" % [time, frame.visible, frame.position, frame.size, frame.modulate.a])
		await _shot(out_dir, "loss2_%04.1fs" % time)

	print("Antidote hint captures written: %d" % _shots)
	quit(0)


func _wait_until_control_returns(runtime: Node) -> void:
	var guard := 0
	while bool(runtime.call("is_control_lost")) and guard < 2000:
		await process_frame
		guard += 1


func _restore_mutation(runtime: Node) -> void:
	var threshold: float = runtime.call("get_critical_threshold")
	var guard := 0
	while float(runtime.call("get_mutation")) > threshold and guard < 50:
		runtime.call("use_antidote")
		guard += 1
		await _frames(2)


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _shot(out_dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := out_dir.path_join("%s.png" % name)
	image.save_png(path)
	_shots += 1
	print("saved ", path)
