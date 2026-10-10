extends SceneTree

const CATALOG := preload("res://game/bootstrap/app/planning_catalog.gd")
const UPDATED_MODELS: Array[String] = [
	"03_book_case", "03_book_case_small", "03_book_case_with_back",
	"03_book_case_with_back_small", "03_bookshelf", "03_box_1_metal_dented",
	"03_file_cabinet_large_shelf_fancy", "03_file_cabinet_largest",
	"03_file_cabinet_small_shelf_fancy", "03_file_cabinet_small_with_shelfs",
	"03_file_cabinet_smaller", "03_locker_tall_dented",
	"03_server_rack", "03_server_rack2", "03_server_rack3"
]

const UPDATED_ELECTRONICS: Array[String] = [
	"05_MFU_2_extra_trays_destructible",
	"05_MFU_destructible",
	"05_aircondition_destructible",
	"05_computer_mouse",
	"05_computer_tower_destructible",
	"05_desk_phone",
	"05_keyboard",
	"05_lamp",
	"05_laptop2_destructible",
	"05_laptop_close_destructible",
	"05_laptop_destructible",
	"05_minipc",
	"05_monitor2_destructible",
	"05_monitor3_server_destructible",
	"05_monitor4_server_destructible",
	"05_monitor_destructible",
	"05_monitor_wide_destructible",
	"05_phone_a_base",
	"05_phone_a_base_hang",
	"05_phone_b",
	"05_printer_destructible",
	"05_wall_TV_destructible",
	"05_wall_TV_frameless_destructible",
	"05_wall_hand_dryer_improved"
]

var failures: int = 0
var models: int = 0
var textured_models: int = 0
var shared_maps: Dictionary = {}
var map_bytes := 0
var map_references := 0

const GROUP01_MAPS: Array[String] = [
	"res://models/objects/enviroments/01/textures/unified/group01_albedo.png",
	"res://models/objects/enviroments/01/textures/unified/group01_normal.png",
	"res://models/objects/enviroments/01/textures/unified/group01_orm.png",
]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var fixture := {"scenes": [{"nodes": [0]}], "nodes": [{"mesh": 1}],
		"meshes": [{}, {}]}
	if _source_mesh_indices(fixture).keys() != [1]:
		_fail("Source audit must exclude meshes not attached to any scene.")
	_check_shared_pbr_resources()
	_check_directory("res://models")
	await _check_catalog_models()
	await _check_column_variant()
	if map_bytes > 48 * 1024 * 1024 or map_references <= shared_maps.size():
		_fail("Updated model textures must share compressed resources within 48 MiB.")
	print("Updated model maps: %d references, %d shared textures, %.1f MiB" %
		[map_references, shared_maps.size(), float(map_bytes) / (1024 * 1024)])
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
	print("Checking model textures: " + path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail(path + ": cannot read source")
		return
	file.seek(12)
	var length := file.get_32()
	file.get_32()
	var document: Dictionary = JSON.parse_string(file.get_buffer(length).get_string_from_utf8())
	var expected: Dictionary = {"base": 0, "normal": 0, "orm": 0}
	for mesh_index: int in _source_mesh_indices(document):
		var mesh: Dictionary = document["meshes"][mesh_index]
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
	if path.begins_with("res://models/objects/enviroments/"):
		_check_runtime_profile(instance, path)
	var found: Dictionary = {"base": 0, "normal": 0, "orm": 0}
	_inspect(instance, found)
	for slot: String in expected:
		if int(found[slot]) < int(expected[slot]):
			_fail("%s: imported %s maps %d, expected at least %d" % [path, slot, found[slot], expected[slot]])
	models += 1
	textured_models += int(int(found.base) + int(found.normal) + int(found.orm) > 0)
	instance.free()


func _check_runtime_profile(instance: Node, path: String) -> void:
	for node: Node in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as BaseMaterial3D
			if material == null:
				continue
			for slot in BaseMaterial3D.TEXTURE_MAX:
				var texture := material.get_texture(slot)
				if texture == null or texture.resource_path.begins_with("res://models/objects/textures/"):
					continue
				var limit := 2048 if texture.resource_path in [GROUP01_MAPS[0], "res://models/objects/enviroments/03/textures/unified/group03_albedo.png"] else 1024
				if maxi(texture.get_width(), texture.get_height()) > limit:
					_fail("Runtime environment map exceeds its %d-pixel budget: %s" % [limit, path])

func _source_mesh_indices(document: Dictionary) -> Dictionary:
	var pending: Array = []
	for scene: Dictionary in document.get("scenes", []):
		pending.append_array(scene.get("nodes", []))
	var visited: Dictionary = {}
	var meshes: Dictionary = {}
	while not pending.is_empty():
		var index: int = pending.pop_back()
		if visited.has(index):
			continue
		visited[index] = true
		var node: Dictionary = document["nodes"][index]
		if node.has("mesh"):
			meshes[int(node["mesh"])] = true
		pending.append_array(node.get("children", []))
	return meshes

func _check_catalog_models() -> void:
	var catalog := CATALOG.new()
	catalog._build_environment_catalogs()
	for phone: String in ["phone_a_base", "phone_a_base_hang", "phone_b"]:
		var old_path := "res://models/objects/enviroments/05/09_" + phone + ".glb"
		var new_path := "res://models/objects/enviroments/05/05_" + phone + ".glb"
		if catalog._migrate_scene_path(old_path) != new_path or not ResourceLoader.exists(new_path):
			_fail(old_path + ": renamed phone is unavailable to saved maps")
	for name: String in UPDATED_MODELS + UPDATED_ELECTRONICS:
		var group := name.left(2)
		var entries: Array = catalog.group_catalogs[group]
		var path := "res://models/objects/enviroments/" + group + "/" + name + ".glb"
		var listed := false
		for entry: Dictionary in entries:
			listed = listed or entry.path == path
		if not listed:
			_fail(path + ": missing from planner group " + group)
		var source := (load(path) as PackedScene).instantiate()
		var expected: Dictionary = {"base": 0, "normal": 0, "orm": 0}
		_inspect(source, expected)
		source.free()
		var prop := catalog._instantiate_asset(path) as RigidBody3D
		if prop == null:
			_fail(path + ": planner cannot instantiate prop")
			continue
		root.add_child(prop)
		prop.freeze = true
		var found: Dictionary = {"base": 0, "normal": 0, "orm": 0}
		_inspect(prop, found, true)
		for slot: String in expected:
			if int(found[slot]) < int(expected[slot]):
				_fail(path + ": gameplay prop lost " + slot + " textures")
		if prop.get_node_or_null("Visual") == null or prop.get("_shapes").is_empty():
			_fail(path + ": gameplay visual or collision missing")
		prop.queue_free()
		await process_frame
		print("Planner model textures OK: " + name)

func _inspect(node: Node, found: Dictionary, check_memory: bool = false) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(surface) as BaseMaterial3D
			if material == null:
				continue
			found.base += int(material.albedo_texture != null)
			found.normal += int(material.normal_enabled and material.normal_texture != null)
			found.orm += int(material.get_texture(BaseMaterial3D.TEXTURE_ORM) != null or material.roughness_texture != null)
			if check_memory:
				_record_maps(material)
	for child: Node in node.get_children():
		_inspect(child, found, check_memory)

func _record_maps(material: BaseMaterial3D) -> void:
	for slot in BaseMaterial3D.TEXTURE_MAX:
		var texture := material.get_texture(slot)
		# Authored external decals (e.g. sticky notes) have a separate import policy.
		if texture == null or maxi(texture.get_width(), texture.get_height()) < 512:
			continue
		var path := texture.resource_path
		if not texture is ImageTexture and not path.begins_with("res://models/objects/enviroments/"):
			continue
		var limit := 2048 if path in [GROUP01_MAPS[0], "res://models/objects/enviroments/03/textures/unified/group03_albedo.png"] else 1024
		if maxi(texture.get_width(), texture.get_height()) > limit:
			_fail("Runtime model map exceeds its %d-pixel budget: %s" % [limit, path])
		if texture is ImageTexture and not path.begins_with("res://assets/runtime_shared_maps/"):
			_fail("Updated embedded map was not shared: " + path)
			continue
		map_references += 1
		if shared_maps.has(path):
			if shared_maps[path] != texture:
				_fail("Duplicate allocation for shared map: " + path)
			continue
		shared_maps[path] = texture
		var image := texture.get_image()
		if image == null or not image.is_compressed() or not image.has_mipmaps():
			_fail("Shared map must be VRAM compressed with mipmaps: " + path)
		else:
			map_bytes += image.get_data_size()

func _fail(message: String) -> void:
	failures += 1
	push_error(message)


func _check_shared_pbr_resources() -> void:
	var models: Array[Node3D] = []
	for name: String in ["03_book_case", "03_book_case_small"]:
		var path := "res://models/objects/enviroments/03/" + name + ".glb"
		var scene := load(path) as PackedScene
		if scene == null:
			_fail("Cannot load shared PBR fixture: " + path)
			for model in models:
				model.free()
			return
		models.append(scene.instantiate() as Node3D)
	var first := _normal_textures(models[0])
	var second := _normal_textures(models[1])
	var shared := false
	for texture: Texture2D in first:
		if not texture.resource_path.is_empty() and texture in second:
			shared = true
			break
	if not shared:
		_fail("Bookcase variants must reuse the same external normal Texture2D resource.")
	for model in models:
		model.free()


func _normal_textures(model: Node3D) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as BaseMaterial3D
			if material != null and material.normal_texture != null and material.normal_texture not in result:
				result.append(material.normal_texture)
	return result


func _check_column_variant() -> void:
	var catalog := CATALOG.new()
	catalog._build_environment_catalogs()
	var path := "res://game/presentation/office_floor/public/structural/column_2.tscn"
	if catalog._migrate_scene_path("res://models/objects/enviroments/01/01_column_2.glb") != path:
		_fail("Saved raw Column 2 must reload as a structural column")
	var listed := false
	for entry: Dictionary in catalog.group_catalogs["01"]:
		listed = listed or (entry.path == path and entry.kind == "")
	if not listed:
		_fail("Column 2 is missing from the structural planner palette")
	var column := catalog._instantiate_asset(path)
	if column == null:
		_fail("Column 2 cannot be instantiated for gameplay")
		return
	# Exercise the same hidden parent used during asynchronous mission startup.
	var mission := Node3D.new()
	mission.hide()
	root.add_child(mission)
	mission.add_child(column)
	await process_frame
	await process_frame
	var maps := {"base": 0, "normal": 0, "orm": 0}
	_inspect(column, maps, true)
	for slot: String in maps:
		if int(maps[slot]) == 0:
			_fail("Column 2 lost its " + slot + " texture")
	var body := column.get_node_or_null("Body") as StaticBody3D
	if body == null or body.get_child_count() == 0:
		_fail("Column 2 must have static collision under a hidden mission")
	if not column.is_in_group("camera_occluder"):
		_fail("Column 2 must participate in camera occlusion")
	mission.queue_free()
	await process_frame
