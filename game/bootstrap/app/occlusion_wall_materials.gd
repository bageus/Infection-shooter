extends RefCounted
## Runtime-only materials, restored exactly on mode change or teardown.
const SHADER := preload("res://game/bootstrap/app/occlusion_hole.gdshader")
var records: Dictionary = {}


func add_root(root: Node3D) -> void:
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or records.has(mesh.get_instance_id()):
			continue
		var saved: Array[Material] = []
		var replacements: Array[ShaderMaterial] = []
		for index in mesh.mesh.get_surface_count():
			saved.append(mesh.get_surface_override_material(index))
			var source := mesh.get_active_material(index) as BaseMaterial3D
			# Glass remains authored; only opaque structural surfaces get a hole.
			if source == null or source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				replacements.append(null)
				continue
			var material := _copy_surface(source)
			replacements.append(material)
		if replacements.all(func(value: Variant) -> bool: return value == null):
			continue
		# material_override masks surface overrides: restore it on exit too.
		records[mesh.get_instance_id()] = {"mesh": weakref(mesh), "override": mesh.material_override,
			"saved": saved, "materials": replacements}
		var original_override := mesh.material_override
		mesh.material_override = null
		for index in replacements.size():
			var fallback: Material = original_override if original_override != null else saved[index]
			mesh.set_surface_override_material(index, replacements[index] if replacements[index] != null else fallback)


func _copy_surface(source: BaseMaterial3D) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	var shader := SHADER
	if source.cull_mode != BaseMaterial3D.CULL_BACK:
		shader = Shader.new()
		shader.code = SHADER.code.replace("shader_type spatial;", "shader_type spatial;\nrender_mode " + ("cull_disabled" if source.cull_mode == BaseMaterial3D.CULL_DISABLED else "cull_front") + ";")
	material.shader = shader
	for pair in [["base_color", source.albedo_color], ["base_texture", source.albedo_texture],
		["use_texture", source.albedo_texture != null], ["roughness_value", source.roughness],
		["metallic_value", source.metallic], ["specular_value", source.metallic_specular],
		["uv_scale", source.uv1_scale], ["uv_offset", source.uv1_offset],
		["use_vertex_color", source.vertex_color_use_as_albedo],
		["roughness_texture", source.roughness_texture], ["use_roughness", source.roughness_texture != null],
		["roughness_channel", _channel(source.roughness_texture_channel)],
		["metallic_texture", source.metallic_texture], ["use_metallic", source.metallic_texture != null],
		["metallic_channel", _channel(source.metallic_texture_channel)],
		["ao_texture", source.ao_texture], ["use_ao", source.ao_enabled and source.ao_texture != null],
		["ao_channel", _channel(source.ao_texture_channel)], ["ao_light_affect", source.ao_light_affect],
		["emission_color", source.emission * source.emission_energy_multiplier if source.emission_enabled else Color.BLACK],
		["emission_texture", source.emission_texture], ["use_emission", source.emission_enabled and source.emission_texture != null],
		["normal_texture", source.normal_texture], ["use_normal", source.normal_enabled], ["normal_scale", source.normal_scale]]:
		material.set_shader_parameter(pair[0], pair[1])
	return material


func update_hole(center: Vector2, size: Vector2, radius: float, depth: float) -> void:
	for id in records.keys():
		if records[id].mesh.get_ref() == null:
			records.erase(id)
			continue
		for material: ShaderMaterial in records[id].materials:
			if material == null:
				continue
			material.set_shader_parameter("hole_center", center)
			material.set_shader_parameter("viewport_size", size)
			material.set_shader_parameter("hole_radius", radius)
			material.set_shader_parameter("player_depth", depth)


func clear() -> void:
	for record in records.values():
		var mesh := record.mesh.get_ref() as MeshInstance3D
		if mesh == null:
			continue
		mesh.material_override = record.override
		for index in record.saved.size():
			mesh.set_surface_override_material(index, record.saved[index])
	records.clear()


func _channel(channel: int) -> Vector4:
	return [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1), Vector4(0.333333, 0.333333, 0.333333, 0)][clampi(channel, 0, 4)]
