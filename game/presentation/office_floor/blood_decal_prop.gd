extends Node3D
## Planner blood decoration (ADR-0017): one of the game's blood textures laid
## on the floor or a wall. Size is the node's uniform scale (1 = one metre on
## the long side). It uses a flat textured quad, so it renders the same in
## every renderer and is selectable in the planner like other objects.

const LIBRARY := preload("res://game/presentation/office_floor/blood_texture_library.gd")
const FLOOR_OFFSET := 0.002

## Texture id "<category>_<variant>", e.g. "splatter_03".
@export var texture_name := "splatter_01"
## "floor" or "wall".
@export_enum("floor", "wall", "object") var surface := "floor"
@export var surface_normal := Vector3.UP
@export var attachment_owner := ""
@export var attachment_mesh := ""
var _anchor: WeakRef
var _anchor_transform := Transform3D.IDENTITY
var _projection_pool: Node
var _projection_anchor: WeakRef
var _footprint := Vector2.ONE
var _surface_material: StandardMaterial3D
var _receivers: Array[Dictionary] = []
var _projection_dirty := true
var _projection_transform := Transform3D()
var _last_anchor_transform := Transform3D()


func configure_blood_normal(normal: Vector3) -> void:
	var next := normal.normalized() if not normal.is_zero_approx() else Vector3.UP
	_projection_dirty = _projection_dirty or not surface_normal.is_equal_approx(next)
	surface_normal = next
	if is_inside_tree() and _visual != null:
		if _projection_anchor == null:
			_apply_surface()


func get_blood_attachment() -> Dictionary:
	return {"owner": attachment_owner, "mesh": attachment_mesh}


func configure_blood_attachment(config: Dictionary) -> void:
	attachment_owner = str(config.get("owner", ""))
	attachment_mesh = str(config.get("mesh", ""))


func attach_blood(anchor: Node3D, owner_id: String) -> void:
	_anchor = weakref(anchor)
	attachment_owner = owner_id
	attachment_mesh = str(anchor.name)
	_anchor_transform = anchor.global_transform.affine_inverse() * global_transform
	_last_anchor_transform = anchor.global_transform
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	configure_projection(anchor)


func configure_world(_container: Node3D, impacts: Node) -> void:
	_projection_pool = impacts


func configure_projection(anchor: Node3D) -> void:
	var previous: Node3D = _projection_anchor.get_ref() if _projection_anchor != null else null
	_projection_dirty = _projection_dirty or previous != anchor
	_projection_anchor = weakref(anchor) if anchor != null else null
	if anchor == null and previous != null and _visual != null:
		_rebuild()
	if _visual != null:
		_project_surface()


func _process(_delta: float) -> void:
	var anchor := _anchor.get_ref() as Node3D if _anchor != null else null
	if anchor == null:
		if _visual != null:
			_visual.hide()
		set_process(false)
		return
	if not anchor.global_transform.is_equal_approx(_last_anchor_transform):
		global_transform = anchor.global_transform * _anchor_transform
	else:
		_anchor_transform = anchor.global_transform.affine_inverse() * global_transform
	_last_anchor_transform = anchor.global_transform
	_project_surface()
	if _visual != null:
		_visual.visible = anchor.is_visible_in_tree()


static var _library: RefCounted
var _visual: MeshInstance3D


func _init() -> void:
	set_meta("blood_effect", true)


func _ready() -> void:
	_rebuild()
	set_process(_anchor != null)


# Public planner_decor_v1 (ADR-0017).
func configure_blood(texture_id: String, surface_kind: String) -> void:
	texture_name = texture_id
	surface = surface_kind if surface_kind in ["floor", "wall", "object"] else "floor"
	surface_normal = Vector3.BACK if surface == "wall" else Vector3.UP
	if is_inside_tree():
		_rebuild()
	else:
		set_meta("planning_wall_mount", surface == "wall")


func get_blood_config() -> Dictionary:
	return {"texture": texture_name, "surface": surface, "normal": [surface_normal.x, surface_normal.y, surface_normal.z]}


func _rebuild() -> void:
	set_meta("planning_wall_mount", surface == "wall")
	set_meta("planning_free_place", true)
	if _visual != null:
		_visual.queue_free()
	var entry := texture_entry(texture_name)
	_visual = MeshInstance3D.new()
	_visual.name = "BloodQuad"
	_visual.set_meta("surface_mark", true)
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	var aspect: float = entry.get("aspect", 1.0)
	quad.size = Vector2(1.0, 1.0 / aspect) if aspect >= 1.0 else Vector2(aspect, 1.0)
	_footprint = quad.size
	var material := StandardMaterial3D.new()
	_surface_material = material
	material.albedo_texture = entry.get("texture")
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.35
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = material
	_visual.mesh = quad
	_apply_surface()
	add_child(_visual)


func _apply_surface() -> void:
	var up := Vector3.FORWARD if absf(surface_normal.y) > .9 else Vector3.UP
	_visual.basis = Basis.looking_at(-surface_normal, up)
	_visual.position = surface_normal * FLOOR_OFFSET


static func texture_entry(texture_id: String) -> Dictionary:
	if _library == null:
		_library = LIBRARY.new()
		_library.call("load_assets")
	var category := texture_id.get_slice("_", 0)
	var variant := int(texture_id.get_slice("_", 1))
	for entry: Dictionary in (_library.get("entries") as Dictionary).get(category, []):
		if int(entry.variant) == variant:
			return entry
	return {}


# Every texture the planner can place, as ids.
static func texture_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for category: String in LIBRARY.CATEGORIES:
		for variant in range(1, 10):
			ids.append("%s_%02d" % [category, variant])
	return ids


func _project_surface() -> void:
	if not _projection_dirty and global_transform.is_equal_approx(_projection_transform) and _visual.mesh is ArrayMesh and not _receivers_changed():
		return
	_projection_dirty = false
	_projection_transform = global_transform
	var anchor := _projection_anchor.get_ref() as Node3D if _projection_anchor != null else null
	if anchor == null or not is_instance_valid(_projection_pool):
		return
	var up := Vector3.FORWARD if absf(surface_normal.y) > .9 else Vector3.UP
	var plane := global_basis * Basis.looking_at(-surface_normal, up)
	var projector := Transform3D(plane.orthonormalized(), global_position)
	var size := Vector2(_footprint.x * plane.x.length(), _footprint.y * plane.y.length())
	var entries: Array = _projection_pool.call("projected_geometry", anchor, projector, size, .16, false)
	var combined := ArrayMesh.new()
	var local := global_transform.affine_inverse()
	_receivers.clear()
	for entry in entries:
		_receivers.append({"source": weakref(entry["anchor"]), "transform": entry["anchor"].global_transform})
		var mesh: ArrayMesh = entry["mesh"]
		var mark_transform: Transform3D = local * entry["anchor"].global_transform
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for index in vertices.size():
			vertices[index] = mark_transform * vertices[index]
			normals[index] = (mark_transform.basis.inverse().transposed() * normals[index]).normalized()
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		combined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		combined.surface_set_material(combined.get_surface_count() - 1, _surface_material)
	_visual.mesh = combined
	_visual.transform = Transform3D.IDENTITY


func _receivers_changed() -> bool:
	for receiver in _receivers:
		var source := (receiver["source"] as WeakRef).get_ref() as Node3D
		if source == null or not source.is_inside_tree() or source.is_queued_for_deletion():
			return true
		if not source.global_transform.is_equal_approx(receiver["transform"]):
			return true
	return false
