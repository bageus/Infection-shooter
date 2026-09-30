extends Node3D

# Compress only the caster's elevation; the visible carpet stays authored.
const HEIGHT_RATIO := 1.0 / 3.0
const FLOOR_SURFACE_Y := 0.0135 # Base floor: tile_y 0.001 + half thickness 0.0125.
var _sources: Array[MeshInstance3D] = []
var _casters: Array[MeshInstance3D] = []


func configure(visual: Node3D) -> void:
	_collect_meshes(visual)
	set_notify_transform(true)
	_update_casters()


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var source := node as MeshInstance3D
		if source.mesh != null and source.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			var caster := MeshInstance3D.new()
			caster.name = "CarpetShadowCaster"
			caster.mesh = source.mesh
			caster.material_override = source.material_override
			for surface in source.mesh.get_surface_count():
				caster.set_surface_override_material(surface, source.get_surface_override_material(surface))
			caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			caster.layers = source.layers
			caster.top_level = true
			add_child(caster)
			source.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_sources.append(source)
			_casters.append(caster)
	for child in node.get_children():
		_collect_meshes(child)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_inside_tree():
		_update_casters()


func _update_casters() -> void:
	for index in _sources.size():
		var transform := _sources[index].global_transform
		# Affine compression toward the floor keeps the footprint/UVs intact.
		transform.basis.x.y *= HEIGHT_RATIO
		transform.basis.y.y *= HEIGHT_RATIO
		transform.basis.z.y *= HEIGHT_RATIO
		transform.origin.y = FLOOR_SURFACE_Y + (transform.origin.y - FLOOR_SURFACE_Y) * HEIGHT_RATIO
		_casters[index].global_transform = transform
		_casters[index].visible = _sources[index].visible
