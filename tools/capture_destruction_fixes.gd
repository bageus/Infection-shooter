extends SceneTree
## Renders the open-door glass break, the cooler bottle burst and blood on a pane.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_destruction_fixes.gd -- <out_dir> <suffix>
##
## Writes door_<suffix>.png, cooler_<suffix>.png and blood_glass_<suffix>.png.

const CATALOG := preload("res://game/bootstrap/app/planning_catalog.gd")
const DOOR := preload("res://game/presentation/office_floor/public/structural/sliding_glass_door.tscn")
const WALL := preload("res://game/presentation/office_floor/public/structural/glass_wall_full.tscn")
const BLOOD := preload("res://game/presentation/office_floor/public/blood_effects_3d.tscn")
const IMPACTS := preload("res://game/features/combat/public/impact_effects.gd")
var _out_dir := "/tmp/destruction_review"
var _suffix := "after"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if args.size() > 1:
		_suffix = args[1]
	call_deferred("_capture")


func _stage() -> Node3D:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	floor_body.collision_layer = 1 | 128
	stage.add_child(floor_body)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.42, 0.44, 0.48)
	plane.material = floor_material
	floor_mesh.mesh = plane
	stage.add_child(floor_mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.0
	stage.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.82, 0.84, 0.88)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.8, 0.82, 0.86)
	environment.environment.ambient_light_energy = 0.6
	stage.add_child(environment)
	return stage


func _shoot(stage: Node3D, name: String, from: Vector3, target: Vector3, wait: float) -> void:
	var camera := Camera3D.new()
	camera.fov = 45.0
	stage.add_child(camera)
	camera.look_at_from_position(from, target, Vector3.UP)
	camera.make_current()
	await create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out_dir.path_join("%s_%s.png" % [name, _suffix]))
	stage.queue_free()
	await process_frame


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	await _door()
	await _cooler()
	await _blood()
	quit(0)


func _door() -> void:
	var stage := _stage()
	var door := DOOR.instantiate() as Node3D
	stage.add_child(door)
	var pane: StaticBody3D = door.get_node("GlassBody")
	pane.call("configure_world", stage, null)
	var controller: Node = door.get_node("DoorController")
	controller.set("_swing_side", 1.0)
	controller.set("_open_amount", 1.0)
	controller.call("_update_door_visuals", Vector3(0, 0, 1))
	await create_timer(0.3).timeout
	var glass: MeshInstance3D = pane.get("_glass_nodes")[0]
	var point := (glass.global_transform * glass.get_aabb()).get_center()
	pane.call("_break_glass", point, Vector3(0, 0, -1))
	await _shoot(stage, "door", point + Vector3(2.4, 0.4, 3.2), point + Vector3(0, -0.3, 0), 1.2)


func _cooler() -> void:
	var stage := _stage()
	var catalog := CATALOG.new()
	catalog._build_environment_catalogs()
	var effects := Node3D.new()
	stage.add_child(effects)
	var prop: RigidBody3D = catalog.call("_instantiate_asset", "res://models/objects/enviroments/02/02_water_cooler_bottle_attached_destructible.glb")
	stage.add_child(prop)
	prop.position = Vector3(0, 0.02, 0)
	prop.call("configure_world", effects, null)
	await create_timer(0.5).timeout
	var meshes: Array = prop.get("_shape_meshes")
	for index in meshes.size():
		var mesh := meshes[index] as MeshInstance3D
		if mesh.visible and mesh.name == "Part_008":
			var point := mesh.global_transform * mesh.get_aabb().get_center()
			prop.call("take_projectile_hit_at_shape", 28.0, point, Vector3.BACK, Vector3.FORWARD, "AK", index)
	await _shoot(stage, "cooler", Vector3(1.6, 1.6, 2.6), Vector3(0, 0.9, 0), 0.25)


func _blood() -> void:
	var stage := _stage()
	var backdrop := MeshInstance3D.new()
	var quad := BoxMesh.new()
	quad.size = Vector3(5, 3, 0.1)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.9, 0.9, 0.92)
	quad.material = material
	backdrop.mesh = quad
	backdrop.position = Vector3(0, 1.5, -1.5)
	stage.add_child(backdrop)
	var impacts := IMPACTS.new()
	stage.add_child(impacts)
	var wall := WALL.instantiate() as Node3D
	stage.add_child(wall)
	var blood := BLOOD.instantiate() as Node3D
	stage.add_child(blood)
	blood.call("configure_world", stage, impacts)
	var pane_body: StaticBody3D = wall.get_node("GlassBody")
	pane_body.collision_layer |= 128
	impacts.call("register_surface", pane_body, wall.get_node("Visual"))
	await create_timer(0.4).timeout
	var glass: MeshInstance3D
	for mesh: MeshInstance3D in wall.find_children("*", "MeshInstance3D", true, false):
		if "glass" in mesh.name.to_lower() and mesh.visible and mesh.mesh != null:
			glass = mesh
			break
	var center := glass.global_transform * glass.get_aabb().get_center()
	var normal := Vector3.BACK
	print("glass center ", center, " aabb ", glass.get_aabb().size)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.55, 0.02, 0.03, 0.9))
	gradient.set_color(1, Color(0.55, 0.02, 0.03, 0.0))
	var splat := GradientTexture2D.new()
	splat.gradient = gradient
	splat.fill = GradientTexture2D.FILL_RADIAL
	splat.fill_from = Vector2(0.5, 0.5)
	splat.fill_to = Vector2(1.0, 0.5)
	for offset: Vector3 in [Vector3(-0.3, 0.3, 0), Vector3(0.1, -0.2, 0), Vector3(0.3, 0.4, 0)]:
		var blood_material := StandardMaterial3D.new()
		blood_material.albedo_texture = splat
		blood_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Same projector convention as blood_mark_3d: +Z is the surface normal.
		impacts.call("project_surface", pane_body, Transform3D(Basis(Vector3.RIGHT, Vector3.DOWN, Vector3.BACK).orthonormalized(), center + offset), Vector2(0.4, 0.4), blood_material, 0.08, false)
	await _shoot(stage, "blood_glass", center + normal * 3.2, center, 0.8)
