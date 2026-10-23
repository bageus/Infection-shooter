extends SceneTree
## Renders the building skirt under the exterior windows: from the game camera near the map
## edge, and from a free camera outside the building. Prints the average frame time.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_exterior_facade.gd -- <out_dir> <tag>
##
## Writes <out_dir>/facade_<tag>_game.png and facade_<tag>_outside.png.

const MAIN := preload("res://game/bootstrap/app/main.tscn")
var _out_dir := "/tmp/exterior_facade"
var _tag := "after"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if args.size() > 1:
		_tag = args[1]
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1024, 576)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var game := MAIN.instantiate()
	root.add_child(game)
	current_scene = game
	for i in 20:
		await process_frame
	var player := game.get("player") as Node3D
	player.global_position = Vector3(36.0, 0.0, 26.0)
	for i in 30:
		await process_frame
	await _shot("game")
	var camera := Camera3D.new()
	game.add_child(camera)
	camera.look_at_from_position(Vector3(10.0, -22.0, 52.0), Vector3(22.0, -14.0, 30.0), Vector3.UP)
	camera.make_current()
	for i in 5:
		await process_frame
	await _shot("outside")
	var started := Time.get_ticks_usec()
	for i in 30:
		await process_frame
	print("frame ms: %.2f" % ((Time.get_ticks_usec() - started) / 30000.0))
	quit(0)


func _shot(spot: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out_dir.path_join("facade_%s_%s.png" % [_tag, spot]))
