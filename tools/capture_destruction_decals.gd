extends SceneTree
## Renders a desk, a chair and a partition hit by a grenade blast on the shared floor.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_destruction_decals.gd -- <out_dir> <suffix>
##
## Writes decals_<suffix>.png. Run once before and once after a change to compare.

const FLOOR := preload("res://game/presentation/office_floor/public/base_floor_renderer.gd")
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const MODELS := [
	"res://models/objects/enviroments/08/08_office_desk_2.glb",
	"res://models/objects/enviroments/06/06_office_chair_2.glb",
	"res://models/objects/enviroments/08/08_divider_full_H_desk.glb",
]
var _out_dir := "/tmp/destruction_review"
var _suffix := "after"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if args.size() > 1:
		_suffix = args[1]
	call_deferred("_capture")


func _capture() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_view := FLOOR.new()
	stage.add_child(floor_view)
	var effects := Node3D.new()
	stage.add_child(effects)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.0
	stage.add_child(camera)
	camera.look_at_from_position(Vector3(0, 9, 0.01), Vector3.ZERO)
	camera.current = true
	var light := DirectionalLight3D.new()
	stage.add_child(light)
	light.rotation_degrees = Vector3(-65, -15, 0)
	var props: Array[RigidBody3D] = []
	for index in MODELS.size():
		var prop := PROP.instantiate() as RigidBody3D
		prop.set("model_path", MODELS[index])
		prop.position = Vector3(-3.2 + index * 3.2, 0, 0)
		stage.add_child(prop)
		prop.freeze = true
		prop.call("configure_world", effects, null)
		prop.call("configure_glass_debris", floor_view)
		props.append(prop)
	for frame in 4:
		await physics_frame
	for prop in props:
		prop.call("take_projectile_hit", 400.0, Vector3.UP, Vector3.BACK, Vector3.FORWARD, "GRENADE")
		if prop.get("_damage") and prop.get("_damage").transition_pending:
			prop.call("_apply_damage", Vector3.UP, Vector3.FORWARD)
	for frame in 240:
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_out_dir)
	root.get_texture().get_image().save_png(_out_dir.path_join("decals_%s.png" % _suffix))
	quit(0)
