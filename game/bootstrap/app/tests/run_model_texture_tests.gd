extends SceneTree

var failures: int = 0
var models: int = 0
var textured_models: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_check_directory("res://models")
	print("Model texture tests: %d models, %d textured models, %d failures" % [models, textured_models, failures])
	quit(1 if failures > 0 else 0)

func _check_directory(path: String) -> void:
	if FileAccess.file_exists(path + "/.gdignore"):
		return
	for entry: String in ResourceLoader.list_directory(path):
		if entry.ends_with("/"):
			_check_directory(path + "/" + entry.trim_suffix("/"))
		elif entry.ends_with(".glb"):
			_check_model(path + "/" + entry)

func _check_model(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail(path + ": cannot read source")
		return
	file.seek(12)
	var length := file.get_32()
	file.get_32()
	var document: Dictionary = JSON.parse_string(file.get_buffer(length).get_string_from_utf8())
	var expected: Dictionary = {"base": 0, "normal": 0, "orm": 0}
	for mesh: Dictionary in document.get("meshes", []):
		for primitive: Dictionary in mesh.get("primitives", []):
			var index: int = primitive.get("material", -1)
			if index < 0:
				continue
			var material: Dictionary = document["materials"][index]
			var pbr: Dictionary = material.get("pbrMetallicRoughness", {})
			expected.base += int(pbr.has("baseColorTexture"))
			expected.normal += int(material.has("normalTexture"))
			expected.orm += int(pbr.has("metallicRoughnessTexture"))
	var scene := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if scene == null:
		_fail(path + ": cannot load imported model")
		return
	var instance := scene.instantiate()
	var found: Dictionary = {"base": 0, "normal": 0, "orm": 0}
	_inspect(instance, found)
	for slot: String in expected:
		if int(found[slot]) < int(expected[slot]):
			_fail("%s: imported %s maps %d, expected at least %d" % [path, slot, found[slot], expected[slot]])
	models += 1
	textured_models += int(int(found.base) + int(found.normal) + int(found.orm) > 0)
	instance.free()

func _inspect(node: Node, found: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(surface) as BaseMaterial3D
			if material == null:
				continue
			found.base += int(material.albedo_texture != null)
			found.normal += int(material.normal_enabled and material.normal_texture != null)
			found.orm += int(material.get_texture(BaseMaterial3D.TEXTURE_ORM) != null or material.roughness_texture != null)
	for child: Node in node.get_children():
		_inspect(child, found)

func _fail(message: String) -> void:
	failures += 1
	push_error(message)
