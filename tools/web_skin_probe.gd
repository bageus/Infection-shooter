extends Node3D
const SKINS := preload("res://game/features/infected/body_skin_materials.gd")
const BAKE := preload("res://game/features/infected/body_blood_bake.gd")
const POISON := preload("res://game/features/infected/poison_tint.gdshader")
var errors: Array[String] = []
var instances: Array[MeshInstance3D] = []

func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.04, 0.04, 0.04)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 1.0
	add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 15
	add_child(camera)
	camera.look_at_from_position(Vector3(6, -4.5, 20), Vector3(6, -4.5, 0))
	camera.make_current()
	var source := StandardMaterial3D.new()
	source.albedo_color = Color(0.7, 0.7, 0.7)
	var pool := SKINS.new([source, source])
	var mesh := _mesh()
	for i in 129:
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.position = Vector3(i % 13, -floori(i / 13.0), 0)
		var lease: RefCounted = pool.acquire()
		for surface in 2:
			instance.set_surface_override_material(surface, lease.materials[surface])
		lease.bind(instance)
		add_child(instance)
		instances.append(instance)
	for i in [0, 128]:
		var lease: RefCounted = instances[i].get_meta("body_skin_lease")
		var red := BAKE.create_mask()
		red.fill(Color(1, 0, 0))
		lease.upload([red, BAKE.create_mask()])
		lease.bind(instances[i], true)
	var poison := ShaderMaterial.new()
	poison.shader = POISON
	instances[2].material_overlay = poison
	instances[2].set_instance_shader_parameter(&"fade", 0.25)
	for frame in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(image != null and not image.is_empty(), "viewport readback")
	if image != null:
		for i in [0, 128]:
			var left := _sample(image, camera, instances[i].position + Vector3(-0.2, 0, 0))
			var right := _sample(image, camera, instances[i].position + Vector3(0.2, 0, 0))
			_check(left.r > left.g * 1.5 and left.r > left.b * 1.5, "blood on left surface " + str(i))
			_check(absf(right.r - right.g) < 0.06, "clean right surface " + str(i))
		var clean := _sample(image, camera, instances[1].position + Vector3(-0.2, 0, 0))
		_check(absf(clean.r - clean.g) < 0.06, "clean neighbor")
	var per_body := OS.has_feature("web")
	_check((instances[0].get_active_material(0) == instances[127].get_active_material(0)) != per_body, "page material sharing matches the renderer path")
	_check(instances[0].get_active_material(0) != instances[128].get_active_material(0), "overflow page material")
	_check(float(instances[2].get_instance_shader_parameter(&"fade")) == 0.25, "poison fade")
	_check((instances[2].get_meta("body_skin_lease") as RefCounted).selector(instances[2]) == -1.0, "poison blood independence")
	var result := {"errors": errors, "instances": 129, "surfaces": 258, "slots": [0, 1], "array_layers": 128, "renderer": RenderingServer.get_video_adapter_name(), "draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)}
	print("WEB_SKIN_PROBE ", JSON.stringify(result))
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.skinProbeResult = " + JSON.stringify(result))

func _mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for side in 2:
		var x0 := -0.4 + side * 0.4
		var points := PackedVector3Array([Vector3(x0,-0.4,0), Vector3(x0+0.4,-0.4,0), Vector3(x0+0.4,0.4,0), Vector3(x0,0.4,0)])
		var custom := PackedFloat32Array()
		for point in points:
			custom.append_array([point.x, point.y, point.z, 1.0])
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = points
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)])
		arrays[Mesh.ARRAY_CUSTOM0] = custom
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,2,1,0,3,2])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	return mesh

func _sample(image: Image, camera: Camera3D, point: Vector3) -> Color:
	var pixel := camera.unproject_position(point)
	return image.get_pixel(clampi(roundi(pixel.x), 0, image.get_width()-1), clampi(roundi(pixel.y), 0, image.get_height()-1))

func _check(ok: bool, label: String) -> void:
	if not ok:
		errors.append(label)
		push_error(label)
