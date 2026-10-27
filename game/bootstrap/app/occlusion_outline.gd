extends RefCounted
## Yellow rim copy of an item: a stencil mask of its footprint plus a screen-space expanded pass over it.
const MASK_SHADER := preload("res://game/bootstrap/app/occlusion_outline_mask.gdshader")
const RIM_SHADER := preload("res://game/bootstrap/app/occlusion_outline.gdshader")
const TINT := Color(1.0, 0.82, 0.1, 1.0)
var target: WeakRef
var shown := false
var copies: Array[MeshInstance3D] = []


func _init(node: Node3D) -> void:
	target = weakref(node)


func set_revealed(value: bool) -> void:
	if value == shown:
		return
	shown = value
	if copies.is_empty() and value:
		_build()
	for copy in copies:
		if is_instance_valid(copy):
			copy.visible = value


func _build() -> void:
	var node := target.get_ref() as Node3D
	if node == null:
		return
	for source: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		# Beacons, glows and lock icons are decoration, not the item.
		if source.mesh == null or source.has_meta("occlusion_copy") or source.has_meta("planning_bounds_excluded") or source.mesh is QuadMesh or not source.is_visible_in_tree():
			continue
		var rim := ShaderMaterial.new()
		rim.shader = RIM_SHADER
		rim.render_priority = 21
		rim.set_shader_parameter("tint", TINT)
		rim.set_shader_parameter("centre", source.mesh.get_aabb().get_center())
		var mask := ShaderMaterial.new()
		mask.shader = MASK_SHADER
		mask.render_priority = 20
		mask.next_pass = rim
		var copy := MeshInstance3D.new()
		copy.name = "OccludedOutline"
		copy.set_meta("occlusion_copy", true)
		copy.mesh = source.mesh
		copy.skin = source.skin
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		copy.material_override = mask
		source.add_child(copy)
		copies.append(copy)


func clear() -> void:
	for copy in copies:
		if is_instance_valid(copy):
			copy.free()
	copies.clear()
	shown = false
