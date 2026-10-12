extends SceneTree
## Planner views of the group 13 save pass: the same spots before and after the
## automatic light switches, alarms and call points are placed.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_wall_fixtures.gd -- <out_dir>
##
## Writes <out_dir>/wall_fixtures_{door,fire_door,overview}_{before,after}.png.

const MAIN := preload("res://game/bootstrap/app/main.tscn")
const VIEWS := {
	"door": [Vector3(-5.2, 1.7, -1.6), Vector3(-8.0, 1.1, -3.0)],
	"door_back": [Vector3(-11.0, 1.7, -4.6), Vector3(-8.0, 1.1, -3.0)],
	"fire_door": [Vector3(-0.8, 1.9, 0.6), Vector3(2.0, 1.2, -1.09)],
	"overview": [Vector3(0.0, 7.5, 9.5), Vector3(0.0, 1.0, 0.0)]
}
var _out_dir := "/tmp/wall_fixtures"
var _planner: Node
var _camera: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var game := MAIN.instantiate()
	root.add_child(game)
	current_scene = game
	for i in 40:
		await process_frame
	_planner = game.get("planning_mode")
	_planner.call("enter")
	_camera = _planner.get("camera")
	for name: String in VIEWS:
		await _shot(name, "before")
	var storage: Object = _planner.get("storage")
	print("Save pass: ", storage.call("enforce_wall_fixtures"))
	for i in 10:
		await process_frame
	for name: String in VIEWS:
		await _shot(name, "after")
	game.free()
	await process_frame
	quit()


func _shot(name: String, tag: String) -> void:
	var view: Array = VIEWS[name]
	_camera.global_position = view[0]
	_camera.look_at(view[1], Vector3.UP)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/wall_fixtures_%s_%s.png" % [_out_dir, name, tag])
