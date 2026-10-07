extends Node3D
## Draws every project spatial shader once, sub-pixel in front of the camera,
## so the renderer compiles them at mission start instead of on the first
## grenade, skill or blood splash (Compatibility/Web compiles on first draw).
const ROOT := "res://game"
const DISTANCE := 0.25
const QUAD_SIZE := 0.0005
const FRAMES := 3

var shader_count := 0
var _frames_left := FRAMES


func setup(camera: Camera3D) -> void:
	name = "ShaderWarmup"
	camera.add_child(self)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * QUAD_SIZE
	for path in spatial_shader_paths():
		var material := ShaderMaterial.new()
		material.shader = load(path) as Shader
		var mesh := MeshInstance3D.new()
		mesh.mesh = quad
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.position = Vector3(0.0, 0.0, -DISTANCE)
		add_child(mesh)
		shader_count += 1


func _process(_delta: float) -> void:
	_frames_left -= 1
	if _frames_left <= 0:
		queue_free()


static func spatial_shader_paths(directory: String = ROOT) -> PackedStringArray:
	var result := PackedStringArray()
	for entry: String in ResourceLoader.list_directory(directory):
		if entry.ends_with("/"):
			if entry != "tests/":
				result.append_array(spatial_shader_paths(directory.path_join(entry.trim_suffix("/"))))
		elif entry.ends_with(".gdshader"):
			var path := directory.path_join(entry)
			var shader := load(path) as Shader
			if shader != null and shader.get_mode() == Shader.MODE_SPATIAL:
				result.append(path)
	return result
