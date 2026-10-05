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


func configure_blood_normal(normal: Vector3) -> void:
	surface_normal = normal.normalized() if not normal.is_zero_approx() else Vector3.UP
	if is_inside_tree() and _visual != null:
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
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


func _process(_delta: float) -> void:
	var anchor := _anchor.get_ref() as Node3D if _anchor != null else null
	if anchor == null:
		set_process(false)
		return
	global_transform = anchor.global_transform * _anchor_transform
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
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	var aspect: float = entry.get("aspect", 1.0)
	quad.size = Vector2(1.0, 1.0 / aspect) if aspect >= 1.0 else Vector2(aspect, 1.0)
	var material := StandardMaterial3D.new()
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
