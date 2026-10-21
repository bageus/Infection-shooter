extends SceneTree
## Renders broken tables (round, regular, desk-height pedestal) 5 s after the break.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_table_breakup.gd -- <out_dir> <suffix>
##
## Writes table_<name>_<suffix>.png. Run once before and once after a change to compare.

const FLOOR := preload("res://game/presentation/office_floor/public/base_floor_renderer.gd")
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const STAGED := preload("res://game/presentation/office_floor/public/props/07_table.tscn")
const DIR := "res://models/objects/enviroments/07/"
const FLOOR_TOP := 0.0135
const CASES := {
	"circular": ["07_table_circular"],
	"regular": ["07_table", "07_coffee_table"],
	"desk": ["07_table_square_tall"],
}
var _out_dir := "/tmp/destruction_review"
var _suffix := "after"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if args.size() > 1:
		_suffix = args[1]
	call_deferred("_capture_all")


func _capture_all() -> void:
	for case_name: String in CASES:
		await _capture(case_name, CASES[case_name])
	quit(0)


func _capture(case_name: String, models: Array) -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_view := FLOOR.new()
	stage.add_child(floor_view)
	var ground := StaticBody3D.new()
	ground.collision_layer = 3
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(30, 1, 30)
	ground_shape.shape = ground_box
	ground_shape.position.y = FLOOR_TOP - 0.5
	ground.add_child(ground_shape)
	stage.add_child(ground)
	var effects := Node3D.new()
	stage.add_child(effects)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 1.7, 2.5), Vector3(0, 0.3, 0))
	camera.current = true
	var light := DirectionalLight3D.new()
	stage.add_child(light)
	light.rotation_degrees = Vector3(-55, -25, 0)
	var staged: Array[Node] = []
	var props: Array[RigidBody3D] = []
	for index in models.size():
		var x := (index - (models.size() - 1) * 0.5) * 3.0
		if models[index] == "07_table":
			var table := STAGED.instantiate()
			stage.add_child(table)
			table.position = Vector3(x, FLOOR_TOP, 0)
			staged.append(table)
		else:
			var prop := PROP.instantiate() as RigidBody3D
			prop.set("model_path", DIR + models[index] + ".glb")
			stage.add_child(prop)
			prop.position = Vector3(x, FLOOR_TOP, 0)
			prop.freeze = true
			prop.call("configure_world", effects, null)
			prop.call("configure_glass_debris", floor_view)
			props.append(prop)
	for frame in 6:
		await physics_frame
	for table in staged:
		table.call("_switch_to_modular")
		for frame in 3:
			await physics_frame
		for leg in ["Leg_BL", "Leg_BR"]:
			table.call("hit_piece", leg, table.global_position + Vector3(0, 0.3, 0), Vector3.FORWARD, 999.0, "AK")
			for frame in 3:
				await physics_frame
	for prop in props:
		for shot in 8:
			prop.call("take_projectile_hit", 400.0, prop.global_position + Vector3(0, 0.5, 0), Vector3.UP, Vector3.FORWARD, "GRENADE")
			if prop.get("_damage").transition_pending:
				prop.call("_apply_damage", prop.global_position + Vector3(0, 0.5, 0), Vector3.FORWARD)
	for frame in 300:
		await physics_frame
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_out_dir)
	root.get_texture().get_image().save_png(_out_dir.path_join("table_%s_%s.png" % [case_name, _suffix]))
	stage.queue_free()
	await process_frame
