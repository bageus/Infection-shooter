extends RefCounted
## Runtime-only materials, restored exactly on mode change or teardown.
const SHADER := preload("res://game/bootstrap/app/occlusion_hole.gdshader")
var records: Dictionary = {}


var pending: Array[WeakRef] = []
var queued: Dictionary = {}
var surface_cache: Dictionary = {}
var shader_cache: Dictionary = {}
var active_materials: Array[ShaderMaterial] = []
const SURFACES_PER_FRAME := 12


func add_root(root: Node3D) -> void:
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or records.has(mesh.get_instance_id()) or queued.has(mesh.get_instance_id()):
			continue
		if not mesh.is_visible_in_tree() or absf(mesh.global_basis.determinant()) < .00000001:
			continue
		queued[mesh.get_instance_id()] = true
		pending.append(weakref(mesh))


func _install(mesh: MeshInstance3D) -> void:
	if mesh.mesh == null:
		return
	var saved: Array[Material] = []
	var replacements: Array[ShaderMaterial] = []
	for index in mesh.mesh.get_surface_count():
		saved.append(mesh.get_surface_override_material(index))
		var source := mesh.get_active_material(index) as BaseMaterial3D
		if source == null or source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			replacements.append(null)
			continue
		var replacement := _copy_surface(source)
		replacements.append(replacement)
	if replacements.all(func(value: Variant) -> bool: return value == null):
		return
	records[mesh.get_instance_id()] = {"mesh": weakref(mesh), "override": mesh.material_override,
		"saved": saved, "materials": replacements}
	var original_override := mesh.material_override
	mesh.material_override = null
	for index in replacements.size():
		var fallback: Material = original_override if original_override != null else saved[index]
		mesh.set_surface_override_material(index, replacements[index] if replacements[index] != null else fallback)


func _copy_surface(source: BaseMaterial3D) -> ShaderMaterial:
	if surface_cache.has(source):
		return surface_cache[source]
	var material := ShaderMaterial.new()
	var shader := SHADER
	if source.cull_mode != BaseMaterial3D.CULL_BACK:
		if not shader_cache.has(source.cull_mode):
			var variant := Shader.new()
			variant.code = SHADER.code.replace("shader_type spatial;", "shader_type spatial;\nrender_mode " + ("cull_disabled" if source.cull_mode == BaseMaterial3D.CULL_DISABLED else "cull_front") + ";")
			shader_cache[source.cull_mode] = variant
		shader = shader_cache[source.cull_mode]
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
	surface_cache[source] = material
	active_materials.append(material)
	return material


func update_hole(center: Vector2, size: Vector2, radius: float, depth: float) -> void:
	# Bound initial GPU resource/compilation work when a real map has many walls.
	for _i in mini(SURFACES_PER_FRAME, pending.size()):
		var mesh := pending.pop_front().get_ref() as MeshInstance3D
		if mesh != null:
			queued.erase(mesh.get_instance_id())
			_install(mesh)
	for id in records.keys():
		if records[id].mesh.get_ref() == null:
			records.erase(id)
	for material in active_materials:
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
		for index in mini(record.saved.size(), mesh.mesh.get_surface_count()) if mesh.mesh != null else 0:
			mesh.set_surface_override_material(index, record.saved[index])
	records.clear()
	pending.clear()
	queued.clear()
	surface_cache.clear()
	shader_cache.clear()
	active_materials.clear()


func _channel(channel: int) -> Vector4:
	return [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1), Vector4(0.333333, 0.333333, 0.333333, 0)][clampi(channel, 0, 4)]

