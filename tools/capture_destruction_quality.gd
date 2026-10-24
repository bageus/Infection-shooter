extends SceneTree
## Renders a cluster of office props after one grenade blast at a chosen destruction quality.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_destruction_quality.gd -- <out_dir> <level 0|1|2> [close|gameplay]
##
## Writes destruction_quality_<level>_<mode>.png (gameplay: 14 m isometric camera, fov 50; close: 7 m).

const FLOOR := preload("res://game/presentation/office_floor/public/base_floor_renderer.gd")
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const BLAST := preload("res://game/presentation/office_floor/blast_effect.gd")
const QUALITY := preload("res://game/core/vfx/public/destruction_quality.gd")
const MODELS := [
	"07/07_table_circular", "08/08_office_desk_2", "08/08_divider_full_H_desk", "06/06_office_chair_2",
	"05/05_computer_tower_destructible", "04/04_cardboard_boxes_1", "10/10_armchair_green_destructible", "01/01_wood_slat_partition_destructible",
]
var _out_dir := "/tmp/destruction_review"
var _level := 1
var _mode := "gameplay"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if args.size() > 1:
		_level = int(args[1])
	if args.size() > 2:
		_mode = args[2]
	call_deferred("_capture")


func _capture() -> void:
	seed(11)
	QUALITY.set_level(_level)
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_view := FLOOR.new()
	stage.add_child(floor_view)
	var effects := Node3D.new()
	stage.add_child(effects)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.fov = 50.0
	var distance := 14.0 if _mode == "gameplay" else 7.0
	camera.position = Vector3(0, 0, distance).rotated(Vector3.RIGHT, deg_to_rad(-37.3)).rotated(Vector3.UP, deg_to_rad(45))
	camera.rotation_degrees = Vector3(-37.3, 45, 0)
	camera.current = true
	var light := DirectionalLight3D.new()
	stage.add_child(light)
	light.rotation_degrees = Vector3(-65, -15, 0)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.2, 60)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.1
	stage.add_child(floor_body)
	for index in MODELS.size():
		var prop := PROP.instantiate() as RigidBody3D
		prop.set("model_path", "res://models/objects/enviroments/" + MODELS[index] + ".glb")
		prop.collision_mask = 3
		stage.add_child(prop)
		prop.global_position = Vector3(-1.8 + 1.2 * (index % 4), 0.05, -0.7 + 1.4 * (index / 4))
		prop.call("configure_world", effects, null)
		prop.call("configure_glass_debris", floor_view)
	for frame in 10:
		await physics_frame
	var host := Node3D.new()
	stage.add_child(host)
	BLAST.detonate(host, Vector3(0, 0.4, 0), 5.5, false)
	for frame in 420:
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_out_dir)
	root.get_texture().get_image().save_png(_out_dir.path_join("destruction_quality_%d_%s.png" % [_level, _mode]))
	quit(0)
