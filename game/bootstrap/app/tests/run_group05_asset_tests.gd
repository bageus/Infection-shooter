extends SceneTree
## Cold geometry, on-demand transitions, shared PBR resources and instance isolation.
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const CATALOG := preload("res://game/bootstrap/app/planning_catalog.gd")
const ROOT_PATH := "res://models/objects/enviroments/05/"
const REGISTRY := preload("res://models/objects/enviroments/05/materials.json")
const MANIFEST := preload("res://models/objects/enviroments/05/lazy_stages.json")
var failures := 0
var materials: Dictionary = {}
var stage: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var paths: Array = MANIFEST.data.keys()
	paths.sort()
	for file: String in paths:
		_check_authored_materials(file)
		await _check_model(file)
	await _check_isolation()
	var catalog := CATALOG.new()
	catalog._build_environment_catalogs()
	_expect(catalog.group_catalogs["05"].size() == 22, "Damage resources never enter the palette.")
	stage.queue_free()
	await process_frame
	print("Group05 atlas/lazy stages: %d failure(s); %d shared materials." % [failures, materials.size()])
	quit(failures)


func _spawn(file: String) -> RigidBody3D:
	var prop := PROP.instantiate() as RigidBody3D
	prop.set("model_path", ROOT_PATH + file)
	prop.call("configure_world", stage, null)
	stage.add_child(prop)
	prop.freeze = true
	return prop


func _check_model(file: String) -> void:
	var raw := (load(ROOT_PATH + file) as PackedScene).instantiate()
	_expect(raw.get_node("Intact").find_children("*", "MeshInstance3D", true, false).size() <= 2, file + ": cheap cold geometry.")
	_check_materials(raw, true)
	raw.free()
	var prop := _spawn(file)
	var geometry: RefCounted = prop.get("_geometry")
	var visual := prop.get_node("Visual")
	_expect(not prop.get("_shapes").is_empty(), file + ": intact collision.")
	var groups: Array = prop.get("_variants").duplicate()
	groups.append_array(prop.get("_stages"))
	_expect(groups.size() == MANIFEST.data[file].size(), file + ": all authored stage names retained.")
	for group: Node3D in groups:
		_expect(group.get_child_count() == 0 and group.has_meta(&"lazy_stage_path"), file + ": no cold damage meshes.")
	_check_materials(visual)
	if groups.is_empty():
		prop.queue_free()
		await process_frame
		return
	var first: Node3D = groups[0]
	var started := Time.get_ticks_usec()
	for i in 80:
		if first.get_child_count() > 0:
			break
		prop.call("take_projectile_hit", 30.0 if not prop.get("_variants").is_empty() else 400.0, prop.global_position, Vector3.UP, Vector3.FORWARD, "UZI" if not prop.get("_variants").is_empty() else "GRENADE")
		await process_frame
	_expect(first.get_child_count() > 0 and not first.has_meta(&"lazy_stage_path"), file + ": projectile loads required geometry.")
	print("Group05 first transition %s: %.2f ms (includes frames)." % [file, (Time.get_ticks_usec() - started) / 1000.0])
	var count := first.get_child_count()
	_expect(geometry.call("ensure_group", first) and first.get_child_count() == count, file + ": repeated access is idempotent.")
	_check_materials(visual)
	for group: Node3D in groups:
		if group != first:
			_expect(group.get_child_count() == 0, file + ": later stages remain cold.")
			_expect(geometry.call("ensure_group", group) and group.get_child_count() > 0, file + ": later resource is valid.")

	prop.queue_free()
	for child: Node in stage.get_children():
		if child != prop:
			child.queue_free()
	await process_frame


func _check_materials(node: Node, strict: bool = false) -> void:
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			if not strict and (material == null or not REGISTRY.data.has(material.resource_name)):
				continue
			_expect(material != null and REGISTRY.data.has(material.resource_name), "Shared PBR material exists.")
			if material == null:
				continue
			var name := material.resource_name
			if materials.has(name):
				_expect(materials[name] == material, "Identical material uses one shared resource: " + name)
			else:
				materials[name] = material
			if name == "Group05Glass":
				continue
			_expect(material.albedo_texture != null and material.normal_texture != null, "Authored albedo and normal retained.")
			_expect(material.get_texture(BaseMaterial3D.TEXTURE_ROUGHNESS) != null, "Packed ORM roughness exists.")
			for slot in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ROUGHNESS]:
				var texture := material.get_texture(slot)
				if texture != null:
					var image := texture.get_image()
					_expect(image != null and image.is_compressed() and image.has_mipmaps(), "Shared maps compressed with mipmaps.")


func _check_isolation() -> void:
	var first := _spawn("05_PC_destructible.glb")
	var second := _spawn("05_PC_destructible.glb")
	var a := first.get("_stages")[0] as Node3D
	var b := second.get("_stages")[0] as Node3D
	var geometry: RefCounted = first.get("_geometry")
	_expect(geometry.call("ensure_group", a), "First instance loads its stage.")
	_expect(b.get_child_count() == 0 and b.has_meta(&"lazy_stage_path"), "Other instance remains cold.")
	var untouched: Array = second.get("_shapes").duplicate()
	a.hide()
	var other_geometry: RefCounted = second.get("_geometry")
	_expect(other_geometry.call("ensure_group", b), "Second instance can load independently.")
	var first_mesh := a.get_child(0) as MeshInstance3D
	var second_mesh := b.get_child(0) as MeshInstance3D
	_expect(first_mesh.mesh == second_mesh.mesh, "Stage geometry resource is shared across instances.")
	_expect(first_mesh != second_mesh, "Stage visibility nodes remain per instance.")
	_expect(second.get("_shapes") == untouched and second.get_node("Visual/Intact").visible, "Other instance keeps geometry and collision.")
	first.queue_free()
	second.queue_free()
	await process_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _check_authored_materials(file: String) -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	_expect(document.append_from_file(ROOT_PATH + file, state) == OK, "GLTF source can be parsed.")
	for original: Material in state.get_materials():
		var shared := load(str(REGISTRY.data[original.resource_name])) as BaseMaterial3D
		for property: String in ["albedo_color", "metallic", "roughness", "normal_scale", "emission", "emission_enabled", "cull_mode"]:
			var before: Variant = original.get(property)
			var after: Variant = shared.get(property)
			var same: bool = before == after
			if before is float:
				same = absf(before - after) < 0.00001
			if before is Color:
				same = (before as Color).is_equal_approx(after as Color)
			_expect(same, file + ": authored " + property + " preserved.")
