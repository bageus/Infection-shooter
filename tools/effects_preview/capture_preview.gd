extends SceneTree
## Headless-free check of the preview: casts every effect and saves a frame.
##   xvfb-run -a godot --path . --script res://tools/effects_preview/capture_preview.gd -- <out_dir>

const SCENE := preload("res://tools/effects_preview/effects_preview.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var out := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "/tmp/effects_preview"
	DirAccess.make_dir_recursive_absolute(out)
	var preview := SCENE.instantiate()
	root.add_child(preview)
	await create_timer(0.3).timeout
	for name: String in preview.get("_casts"):
		preview.call("_cast", name)
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join(name.validate_filename() + ".png"))
		await create_timer(0.6).timeout
	quit(0)
