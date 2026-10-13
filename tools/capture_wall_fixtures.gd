extends SceneTree
## Planner views of the group 13 save pass: the same spots before and after the
## automatic light switches, alarms and call points are placed.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_wall_fixtures.gd -- <out_dir>
##
## Writes <out_dir>/wall_fixtures_<view>_after.png, plus _before for the BEFORE views.

const MAIN := preload("res://game/bootstrap/app/main.tscn")
const VIEWS := {
	"column_a": [Vector3(12.3, 2.4, 12.3), Vector3(10.1, 1.5, 10.1)],
	"column_b": [Vector3(32.2, 2.4, 2.2), Vector3(30.0, 1.5, 0.0)],
	"door_front": [Vector3(5.6, 2.0, 6.6), Vector3(8.0, 1.2, 5.0)],
	"door_back": [Vector3(10.4, 2.0, 6.6), Vector3(8.0, 1.2, 5.0)],
	"urinals": [Vector3(3.5, 1.6, 9.2), Vector3(3.5, 0.6, 11.7)],
	"hand_dryers": [Vector3(-6.0, 1.8, -10.6), Vector3(-6.0, 1.3, -8.2)],
	"overview": [Vector3(-2.0, 9.0, 8.0), Vector3(-6.0, 1.0, 0.0)]
}
const BEFORE := ["urinals", "hand_dryers", "overview"]
var _out_dir := "/tmp/wall_fixtures"
var _planner: Node
var _camera: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(900, 506)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var game := MAIN.instantiate()
	root.add_child(game)
	current_scene = game
	for i in 40:
		await process_frame
	_planner = game.get("planning_mode")
	_planner.call("enter")
	(_planner.get("ui") as Control).hide()
	_camera = _planner.get("camera")
	for name: String in BEFORE:
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
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/wall_fixtures_%s_%s.png" % [_out_dir, name, tag])
