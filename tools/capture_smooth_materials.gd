extends SceneTree
## Renders the smooth chair/weapon/column/book materials and the desk template guides.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_smooth_materials.gd -- <out_dir>
##
## Writes materials.png, 08_divider_full_H_desk.png, 08_divider_full_U_desk.png and 03_bookshelf.png.

const VISUALS := preload("res://game/bootstrap/app/desk_setup_visuals.gd")
const ROOT := "res://models/objects/enviroments/"
const WEAPONS := "res://models/objects/weapons/"
const MATERIAL_MODELS := [
	[ROOT + "06/06_office_chair.glb", Vector3(-2.4, 0, 0), 0.4],
	[ROOT + "06/06_conference_chair.glb", Vector3(-1.2, 0, 0), -0.4],
	[ROOT + "06/06_simple_chair.glb", Vector3(0, 0, 0), 0.2],
	[ROOT + "01/01_column.glb", Vector3(2.0, 0, -0.5), 0.0],
	[ROOT + "01/01_column_2.glb", Vector3(3.4, 0, -0.5), 0.0],
	[ROOT + "09/09_book_big.glb", Vector3(-1.0, 0.02, 1.4), 0.3],
	[ROOT + "09/09_book_fat.glb", Vector3(-0.6, 0.02, 1.4), 0.1],
	[ROOT + "09/09_book_folder.glb", Vector3(-0.2, 0.02, 1.4), 0.5],
	[ROOT + "09/09_book_small.glb", Vector3(0.2, 0.02, 1.4), 0.0],
	[WEAPONS + "ak_rifle_lowpoly.glb", Vector3(1.0, 0.1, 1.5), 0.0],
	[WEAPONS + "pistol_lowpoly.glb", Vector3(2.0, 0.1, 1.5), 0.0],
	[WEAPONS + "shotgun_lowpoly.glb", Vector3(3.0, 0.1, 1.5), 0.0],
]
var _out_dir := "/tmp/smooth_materials"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out_dir = args[0]
	call_deferred("_capture")


func _stage() -> Node3D:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.5, 0.52, 0.55)
	plane.material = floor_material
	floor_mesh.mesh = plane
	stage.add_child(floor_mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
	sun.light_energy = 0.9
	stage.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.08, 0.1, 0.14)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.7, 0.74, 0.8)
	environment.environment.ambient_light_energy = 0.5
	stage.add_child(environment)
	return stage


func _shoot(stage: Node3D, name: String, from: Vector3, target: Vector3) -> void:
	var camera := Camera3D.new()
	camera.fov = 45.0
	stage.add_child(camera)
	camera.look_at_from_position(from, target, Vector3.UP if absf(from.x - target.x) + absf(from.z - target.z) > 0.01 else Vector3.FORWARD)
	camera.make_current()
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out_dir.path_join(name + ".png"))
	stage.queue_free()
	await process_frame


func _desk_shot(model: String, profile_name: String, zones: Array[Dictionary]) -> void:
	var stage := _stage()
	var desk := (load(ROOT + "08/" + model + ".glb") as PackedScene).instantiate() as Node3D
	desk.set_meta("planning_scene_path", ROOT + "08/" + model + ".glb")
	stage.add_child(desk)
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/bootstrap/app/workstations/desks/%s.json" % profile_name))
	var visuals := VISUALS.new()
	stage.add_child(visuals)
	visuals.configure(desk, profile)
	visuals.redraw(zones, 0, 0)
	await _shoot(stage, model, Vector3(0, 3.6, 2.4), Vector3(0, 0.8, 0))


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var stage := _stage()
	for entry: Array in MATERIAL_MODELS:
		var node := (load(entry[0]) as PackedScene).instantiate() as Node3D
		node.position = entry[1]
		node.rotation.y = entry[2]
		stage.add_child(node)
	await _shoot(stage, "materials", Vector3(0.5, 3.0, 6.0), Vector3(0.5, 0.6, 0.4))
	var zone := {"x": 0.0, "z": -0.55, "width": 0.6, "depth": 0.4, "height": 0.904, "angle": 0.0, "name": "A"}
	var zone_b := {"x": 0.6, "z": 0.5, "width": 0.5, "depth": 0.3, "height": 0.904, "angle": 20.0, "name": "B"}
	await _desk_shot("08_divider_full_H_desk", "divider_h", [zone, zone_b])
	await _desk_shot("08_divider_full_U_desk", "divider_u", [zone_b, zone])
	stage = _stage()
	var shelf := (load(ROOT + "03/03_bookshelf.glb") as PackedScene).instantiate() as Node3D
	stage.add_child(shelf)
	await _shoot(stage, "03_bookshelf", Vector3(2.5, 2.2, 3.0), Vector3(0, 0.9, 0))
	quit(0)
