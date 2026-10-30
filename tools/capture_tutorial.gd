extends SceneTree
## Captures tutorial steps: the scale spotlight, the scale picture, the antidote and gas mask steps.
## Run under xvfb with a real renderer: ... --script tools/capture_tutorial.gd -- <output dir>

const HUD := preload("res://game/presentation/prototype_hud/public/prototype_hud.tscn")
const PLAYER := preload("res://game/features/player/public/player.tscn")
const TREE_UI := preload("res://game/bootstrap/app/mutation_tree_ui.gd")
const DIRECTOR := preload("res://game/bootstrap/app/tutorial/tutorial_director.gd")
const PROGRESS := preload("res://game/bootstrap/app/tutorial/tutorial_progress.gd")
const LOCALIZATION := preload("res://game/core/localization/public/ui_translations.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out_dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://tutorial"
	DirAccess.make_dir_recursive_absolute(out_dir)
	LOCALIZATION.apply_language("ru")
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var player := PLAYER.instantiate() as Node3D
	player.name = "Player"
	stage.add_child(player)
	var runtime: Node = player.get("infection_runtime")
	runtime.set_physics_process(false)
	var hud := HUD.instantiate()
	hud.set("player_path", NodePath("../Player"))
	stage.add_child(hud)
	var tree_ui := TREE_UI.new()
	stage.add_child(tree_ui)
	tree_ui.call("configure", runtime)
	var director := DIRECTOR.new()
	stage.add_child(director)
	director.call("configure", player, hud, tree_ui, PROGRESS.new(out_dir.path_join("seen.cfg")))
	runtime.get("_domain").mutation = 12.0
	runtime.call("absorb_mutagen", 0.01)
	var overlay: Node = director.get("overlay")
	for shot in ["scale_spot", "scale_picture", "antidote", "antidote_wise"]:
		await _wait(0.5)
		root.get_texture().get_image().save_png(out_dir.path_join(shot + ".png"))
		overlay.call("finish")
	runtime.get("_domain").mutation = 25.0
	runtime.call("absorb_mutagen", 0.01)
	await _wait(0.7)
	root.get_texture().get_image().save_png(out_dir.path_join("tree_branches.png"))
	for i in 3:
		await _wait(0.4)
		overlay.call("finish")
	await _wait(0.5)
	root.get_texture().get_image().save_png(out_dir.path_join("tree_pick_power_strike.png"))
	quit()


func _wait(seconds: float) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(seconds * 1000.0):
		await process_frame
