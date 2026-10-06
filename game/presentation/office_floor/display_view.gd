extends Node3D

const PROFILES := preload("res://game/presentation/office_floor/display_surface_profiles.gd")
const CONTENT := preload("res://game/presentation/office_floor/display_content.gd")

var prop: Node3D
var registry: Node
var content := CONTENT.new()
var screens: Array[Dictionary] = []
var config: Dictionary = {}
var television := false
var tiled := false
var damaged := false
var powered := false
var elapsed := 0.0
var _group_index := -1
var _next_frame_time := 0.0


func setup(owner_prop: Node3D, path: String, authored: Dictionary, wall: Node) -> void:
	prop = owner_prop
	television = "wall_TV" in path.get_file()
	tiled = "wall_TV_frameless" in path.get_file()
	for profile: Dictionary in PROFILES.new().screens(path):
		_build_screen(profile)
	set_notify_transform(tiled)
	set_registry(wall)
	configure(authored)


func set_registry(wall: Node) -> void:
	if registry == wall:
		return
	if is_instance_valid(registry):
		registry.call("unregister_display", self)
	registry = wall
	if is_instance_valid(registry):
		content = registry.get("content")
		registry.call("register_display", self)
	set_process(registry == null and powered and _has_animation())


func configure(authored: Dictionary) -> void:
	config = authored.duplicate(true)
	powered = not damaged and (str(config.get("power", "auto")) == "on" or
		(str(config.get("power", "auto")) == "auto" and int(config.get("seed", 1)) % 2 == 0))
	_group_index = -1
	_next_frame_time = 0.0
	for i in range(screens.size()):
		var screen := screens[i]
		var dynamic := television or str(config.get("content", "static")) == "dynamic"
		var count := 3 if dynamic else 16
		var noise_seed := int(config.get("seed", 1))
		var index := (noise_seed % count + i * (1 + noise_seed % (count - 1))) % count
		screen["index"] = index
		screen["dynamic"] = dynamic
		screen["atlas_rect"] = Vector4(-1, -1, -1, -1)
		var material := content.material(dynamic, index)
		material.set_shader_parameter("powered", powered)
		(screen["mesh"] as MeshInstance3D).material_override = material
		(screen["light"] as SpotLight3D).visible = powered
	set_process(registry == null and powered and _has_animation())
	if is_instance_valid(registry):
		registry.call("update_animation", self)
		registry.call("request_layout")


func _has_animation() -> bool:
	for screen in screens:
		if screen["dynamic"]:
			return true
	return false


func disable() -> void:
	damaged = true
	configure(config)
	hide()


func tick(seconds: float, frames: Array[Vector4]) -> void:
	elapsed = seconds
	if not powered or not is_visible_in_tree():
		return
	for screen in screens:
		if not bool(screen["dynamic"]):
			continue
		var material := (screen["mesh"] as MeshInstance3D).material_override as ShaderMaterial
		var rectangle := frames[int(screen["index"])]
		if screen.get("atlas_rect") == rectangle:
			continue
		screen["atlas_rect"] = rectangle
		material.set_shader_parameter("atlas_rect", rectangle)


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < _next_frame_time:
		return
	var frames: Array[Vector4] = []
	var delay := INF
	for i in range(3):
		frames.append(content.frame_rect(i, elapsed))
		delay = minf(delay, content.frame_delay(i, elapsed))
	_next_frame_time = elapsed + delay
	tick(elapsed, frames)


func _build_screen(profile: Dictionary) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "DisplaySurface%d" % screens.size()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normal: Vector3 = PROFILES.vector(profile["normal"])
	for point: Array in profile["vertices"]:
		vertices.append(Vector3(float(point[0]), float(point[1]), float(point[2])))
		normals.append(normal)
		uvs.append(Vector2(float(point[3]), float(point[4])))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var surface := ArrayMesh.new()
	surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.mesh = surface
	add_child(mesh)
	var light := SpotLight3D.new()
	light.name = "DisplayGlow%d" % screens.size()
	var right: Vector3 = PROFILES.vector(profile["right"])
	var up: Vector3 = PROFILES.vector(profile["up"])
	var center: Vector3 = PROFILES.vector(profile["center"])
	# A spotlight emits along -Z. The cone is wholly in the screen's front hemisphere.
	light.transform = Transform3D(Basis(-right, up, -normal), center + normal * .008)
	light.spot_angle = 70.0
	light.spot_range = 1.25
	light.light_energy = .16
	light.light_color = Color(.45, .72, 1.0)
	light.spot_attenuation = 1.5
	light.shadow_enabled = true
	add_child(light)
	screens.append({"mesh": mesh, "light": light, "profile": profile, "index": 0, "dynamic": false})


func wall_frame() -> Transform3D:
	var profile: Dictionary = screens[0]["profile"]
	return global_transform * Transform3D(Basis(PROFILES.vector(profile["right"]),
		PROFILES.vector(profile["up"]), PROFILES.vector(profile["normal"])), PROFILES.vector(profile["center"]))


func set_wall_content(index: int, rectangle: Rect2) -> void:
	if screens.is_empty():
		return
	var screen := screens[0]
	if _group_index != index:
		_group_index = index
		screen["index"] = index
		(screen["mesh"] as MeshInstance3D).material_override = content.material(true, index)
		screen["atlas_rect"] = Vector4(-1, -1, -1, -1)
		if is_instance_valid(registry):
			registry.call("update_animation", self)
	var material := (screen["mesh"] as MeshInstance3D).material_override as ShaderMaterial
	material.set_shader_parameter("powered", powered)
	material.set_shader_parameter("content_rect", Vector4(rectangle.position.x, rectangle.position.y,
		rectangle.size.x, rectangle.size.y))


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_instance_valid(registry):
		registry.call("request_layout")


func _exit_tree() -> void:
	if is_instance_valid(registry):
		registry.call("unregister_display", self)
