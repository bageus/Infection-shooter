extends SceneTree
## Verify the real imported assets and palette, including prior saved paths.
const CATALOG := preload("res://game/bootstrap/app/planning_catalog.gd")
const ROOT_PATH := "res://models/objects/enviroments/01/"
var failures := 0
var shared_materials: Dictionary = {}
const ATLAS_PATH := ROOT_PATH + "textures/unified/"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog := CATALOG.new()
	catalog.call("_build_environment_catalogs")
	var entries: Array = catalog.group_catalogs["01"]
	_check(entries.size() == 25, "Group 01 exposes 24 production assets and the test column once")
	var palette_paths := {}
	for entry: Dictionary in entries:
		_check(not palette_paths.has(entry.path), "Palette entry is unique: " + str(entry.path))
		palette_paths[entry.path] = true
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
		if filename == "01_column_2.glb":
			_check_test_column(model)
		else:
			_check_model(model, filename)
		model.free()
		var migrated := ROOT_PATH + filename
		if filename == "01_column_2.glb":
			migrated = catalog.call("_environment_scene_for", filename)
		_check(catalog.call("_migrate_scene_path", ROOT_PATH + "models/" + filename) == migrated, "Nested saved path migrates: " + filename)
	_check(count == 25, "Runtime folder contains 25 models")
	_check(catalog.call("_migrate_scene_path", ROOT_PATH + "models/01_glass_wall_full_breakable(1).glb") == ROOT_PATH + "01_glass_wall_full_breakable.glb", "Glass wall upload name migrates")
	_check(catalog.call("_environment_scene_for", "01_glass_wall_full_breakable.glb").ends_with("glass_wall_full.tscn"), "Glass wall uses its destructible structural scene")
	_check_legacy_stairs(catalog)
	_check_atlas_budget()
	_check_atlas_properties()
	_check(shared_materials.size() == 3, "Production surfaces share three material variants")
	print("Group 01 asset tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _check_model(model: Node3D, filename: String) -> void:
	var expected := load(ATLAS_PATH + "group01_albedo.png") as Texture2D
	var opaque := 0
	var glass := 0
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
			_check(material is ORMMaterial3D and material.get_texture(BaseMaterial3D.TEXTURE_ORM) != null, "Packed ORM assigned: " + filename)
			_check(material.resource_path.begins_with(ROOT_PATH + "materials/"), "External shared material: " + filename)
			if shared_materials.has(material.resource_path):
				_check(shared_materials[material.resource_path] == material, "Same material allocation across models")
			shared_materials[material.resource_path] = material
			_check(material.albedo_texture == expected, "Same albedo allocation")
			_check(material.normal_texture == load(ATLAS_PATH + "group01_normal.png"), "Same normal allocation")
			_check(material.get_texture(BaseMaterial3D.TEXTURE_ORM) == load(ATLAS_PATH + "group01_orm.png"), "Same ORM allocation")
			var arrays := mesh.mesh.surface_get_arrays(surface)
			_check(not (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).is_empty(), "UV present")
			_check(not (arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array).is_empty(), "Tangents present")
	_check(opaque > 0, "Model has textured surfaces: " + filename)
	if filename.begins_with("01_glass_"):
		_check(glass > 0, "Glass stays separate: " + filename)
	if filename == "01_VECTRION_Destructible.glb":
		_check(model.get_node_or_null("Intact") != null and model.get_node_or_null("LargeParts") != null and model.get_node_or_null("JaggedFragments") != null, "VECTRION retains all damage stages")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _check_test_column(model: Node3D) -> void:
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var material := mesh.get_active_material(0) as BaseMaterial3D
		_check(material != null, "Test column retains its material")
		if material != null:
			_check(material.albedo_texture.resource_path == ROOT_PATH + "01_column_2_Image_0.jpg", "Test column retains albedo")
			_check(material.normal_texture.resource_path == ROOT_PATH + "01_column_2_Image_2.jpg", "Test column retains normal")


func _check_legacy_stairs(catalog: RefCounted) -> void:
	for prefix: String in ["", "models/"]:
		_check(catalog.call("_migrate_scene_path", ROOT_PATH + prefix + "01_stairs_2.glb") == ROOT_PATH + "01_stairs.glb", "Duplicate staircase saved path migrates")
	var stairs := catalog.call("_create_asset", ROOT_PATH + "01_stairs_2.glb") as Node3D
	_check(stairs != null and stairs.get("model_path") == ROOT_PATH + "01_stairs.glb", "Direct legacy staircase uses canonical model")
	if stairs != null:
		stairs.free()


func _check_atlas_budget() -> void:
	var bytes := 0
	for kind: String in ["albedo", "normal", "orm"]:
		var texture := load(ATLAS_PATH + "group01_" + kind + ".png") as Texture2D
		_check(texture != null and texture.get_size() == Vector2.ONE * (2048 if kind == "albedo" else 1024), "Atlas has explicit import budget: " + kind)
		if texture != null:
			var image := texture.get_image()
			_check(image != null and image.is_compressed() and image.has_mipmaps(), "Compressed atlas with mipmaps: " + kind)
			if image != null:
				bytes += image.get_data_size()
	_check(bytes <= 6 * 1024 * 1024, "Three atlas maps fit 6 MiB GPU payload budget")
	print("Group 01 shared atlas: %.2f MiB, %d shared materials" % [float(bytes) / (1024 * 1024), shared_materials.size()])


func _check_atlas_properties() -> void:
	var texture := load(ATLAS_PATH + "group01_orm.png") as Texture2D
	# Never decompress the texture's shared CPU image in place.
	var image := texture.get_image().duplicate() as Image
	if image.is_compressed():
		_check(image.decompress() == OK, "ORM can be inspected")
	_check(image.get_pixel(128, 384).b > 0.98, "VECTRION steel tile has metallic = 1")
	_check(image.get_pixel(384, 128).b < 0.02, "Column coating remains nonmetallic")
	var low := 1.0
	var high := 0.0
	for y in range(24, 232, 24):
		for x in range(280, 488, 24):
			var roughness := image.get_pixel(x, y).g
			low = minf(low, roughness)
			high = maxf(high, roughness)
	_check(high - low > 0.15, "Column coating retains roughness variation after 1K import")
