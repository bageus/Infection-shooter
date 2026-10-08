extends SceneTree
## Verify the real imported assets and palette, including prior saved paths.
const CATALOG := preload("res://game/bootstrap/app/planning_catalog.gd")
const ROOT_PATH := "res://models/objects/enviroments/01/"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog := CATALOG.new()
	catalog.call("_build_environment_catalogs")
	var entries: Array = catalog.group_catalogs["01"]
	_check(entries.size() == 25, "Group 01 exposes all 25 assets once")
	for entry: Dictionary in entries:
		_check(ResourceLoader.exists(str(entry.path)), "Palette entry loads: " + str(entry.name))
	var count := 0
	for filename: String in ResourceLoader.list_directory(ROOT_PATH):
		if not filename.ends_with(".glb"):
			continue
		count += 1
		var packed := load(ROOT_PATH + filename) as PackedScene
		_check(packed != null, "Model imports: " + filename)
		if packed == null:
			continue
		var model := packed.instantiate() as Node3D
		_check_model(model, filename)
		model.free()
		_check(catalog.call("_migrate_scene_path", ROOT_PATH + "models/" + filename) == ROOT_PATH + filename, "Nested saved path migrates: " + filename)
	_check(count == 25, "Runtime folder contains all 25 models")
	_check(catalog.call("_migrate_scene_path", ROOT_PATH + "models/01_glass_wall_full_breakable(1).glb") == ROOT_PATH + "01_glass_wall_full_breakable.glb", "Glass wall upload name migrates")
	_check(catalog.call("_environment_scene_for", "01_glass_wall_full_breakable.glb").ends_with("glass_wall_full.tscn"), "Glass wall uses its destructible structural scene")
	print("Group 01 asset tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _check_model(model: Node3D, filename: String) -> void:
	var family := "architecture"
	if filename.begins_with("01_floor_"):
		family = "carpet"
	elif filename.begins_with("01_stairs") or filename.begins_with("01_elevator_cabin"):
		family = "stairs_elevators"
	var prefix := "carpet" if family == "carpet" else "architecture"
	var expected := load(ROOT_PATH + "textures/" + family + "/" + prefix + "_albedo.png") as Texture2D
	_check(expected != null, "Shared texture exists: " + family)
	var opaque := 0
	var glass := 0
	var checked_materials: Dictionary = {}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as BaseMaterial3D
			if material == null:
				continue
			if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				glass += 1
				_check(material.normal_texture == null, "Glass has no new normal map")
				continue
			if material.albedo_texture == null:
				_check(filename == "01_floor_pad.glb" or filename.begins_with("01_elevator_cabin"), "Only rubber border/light/display remain untextured")
				continue
			opaque += 1
			_check(material.normal_enabled and material.normal_texture != null, "Normal map enabled: " + filename)
			_check(material.roughness_texture != null and material.metallic_texture != null, "ORM assigned: " + filename)
			_check(material.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN, "Roughness reads ORM green")
			_check(material.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE, "Metallic reads ORM blue")
			var arrays := mesh.mesh.surface_get_arrays(surface)
			_check(not (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).is_empty(), "UV present")
			_check(not (arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array).is_empty(), "Tangents present")
			if expected != null and not checked_materials.has(material):
				checked_materials[material] = true
				var actual := material.albedo_texture.get_image()
				var reference := expected.get_image()
				_check(actual.get_size() == reference.get_size() and actual.get_pixel(100, 100).is_equal_approx(reference.get_pixel(100, 100)), "Correct atlas family: " + filename)
	_check(opaque > 0, "Model has textured surfaces: " + filename)
	if filename.begins_with("01_glass_"):
		_check(glass > 0, "Glass stays separate: " + filename)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
