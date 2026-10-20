extends RefCounted
## Per-anchor weak registrations; inspect only biomass on the confirmed receiver.
const SFX := preload("res://game/core/audio/public/sound_events.gd")
const ATLAS := preload("res://game/presentation/office_floor/biomass_atlas.gd")
const KEY := &"biomass_impact_audio"
var _anchor: WeakRef
var _piece: WeakRef
var _texture: Texture2D
var _image: Image


func bind(anchor: Node3D, piece: Node3D) -> void:
	unregister()
	if anchor == null or not ATLAS.is_biomass_id(str(piece.get("texture_name"))):
		return
	_anchor = weakref(anchor)
	_piece = weakref(piece)
	var entries: Dictionary = anchor.get_meta(KEY, {})
	entries[piece.get_instance_id()] = weakref(self)
	anchor.set_meta(KEY, entries)


func unregister() -> void:
	var anchor := _anchor.get_ref() as Node3D if _anchor != null else null
	var piece := _piece.get_ref() as Node3D if _piece != null else null
	if anchor != null and piece != null:
		var entries: Dictionary = anchor.get_meta(KEY, {})
		entries.erase(piece.get_instance_id())
		if entries.is_empty(): anchor.remove_meta(KEY)
		else: anchor.set_meta(KEY, entries)
	_anchor = null
	_piece = null


static func play(anchor: MeshInstance3D, point: Vector3, normal: Vector3, parent: Node3D) -> void:
	if anchor == null or not anchor.has_meta(KEY):
		return
	var entries: Dictionary = anchor.get_meta(KEY)
	for id in entries.keys():
		var probe: RefCounted = (entries[id] as WeakRef).get_ref()
		if probe == null:
			entries.erase(id)
		elif probe.call("covers", point, normal):
			SFX.play(parent, &"hit_biomass", point)
			return


func covers(point: Vector3, normal: Vector3) -> bool:
	var piece := _piece.get_ref() as Node3D if _piece != null else null
	if piece == null or not piece.is_inside_tree() or piece.is_queued_for_deletion() or str(piece.get("surface")) != "wall":
		return false
	if not ATLAS.is_biomass_id(str(piece.get("texture_name"))):
		return false
	var visual := piece.get("_visual") as MeshInstance3D
	if visual == null or not visual.is_visible_in_tree() or visual.mesh == null or absf(visual.global_basis.determinant()) < 1e-9:
		return false
	var outward := (visual.global_basis.inverse().transposed() * Vector3.BACK).normalized()
	if outward.dot(normal.normalized()) < 0.9:
		return false
	var local := visual.to_local(point)
	if absf(local.z) > 0.12:
		return false
	var box := visual.mesh.get_aabb()
	var rect := Rect2(Vector2(box.position.x, box.position.y), Vector2(box.size.x, box.size.y))
	if not rect.has_point(Vector2(local.x, local.y)):
		return false
	var uv := Vector2((local.x - rect.position.x) / rect.size.x, (rect.end.y - local.y) / rect.size.y)
	var material := visual.mesh.surface_get_material(0) as ShaderMaterial
	if material == null:
		return false
	var region: Vector4 = material.get_shader_parameter("uv_rect")
	uv = Vector2(region.x, region.y) + uv * Vector2(region.z, region.w)
	if not bool(piece.get("_fused")):
		var pixel := Vector2i(uv * Vector2(ATLAS.ATLAS)).clamp(Vector2i.ZERO, ATLAS.ATLAS - Vector2i.ONE)
		return ATLAS.albedo_bytes()[(pixel.y * ATLAS.ATLAS.x + pixel.x) * 4 + 3] > 127
	var texture := material.get_shader_parameter("albedo_texture") as Texture2D
	if texture == null:
		return false
	if texture != _texture:
		_texture = texture
		_image = texture.get_image()
	return _image != null and _image.get_pixelv(Vector2i(uv * Vector2(_image.get_size())).clamp(Vector2i.ZERO, _image.get_size() - Vector2i.ONE)).a > 0.5
