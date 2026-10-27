extends Node3D
## Planner blood decoration (ADR-0017): one of the game's blood textures laid
## on the floor or a wall. Size is the node's uniform scale (1 = one metre on
## the long side). It uses a flat textured quad, so it renders the same in
## every renderer and is selectable in the planner like other objects.

const SURFACE_DECOR := preload("res://game/presentation/office_floor/public/surface_decor_catalog.gd")
const AMBIENT_SOUNDS := preload("res://game/presentation/office_floor/public/ambient_prop_sounds.gd")
const BLOOD_LEVEL := preload("res://game/core/vfx/public/blood_level.gd")
const LIBRARY := preload("res://game/presentation/office_floor/blood_texture_library.gd")
const BIOMASS := preload("res://game/presentation/office_floor/biomass_atlas.gd")
const BIOMASS_MESH := preload("res://game/presentation/office_floor/biomass_mesh.gd")
const BIOMASS_FIT := preload("res://game/presentation/office_floor/biomass_fit.gd")
const IMPACT_AUDIO := preload("res://game/presentation/office_floor/biomass_impact_audio.gd")
const BIOMASS_CLIP := preload("res://game/presentation/office_floor/biomass_clip.gd")
const BIOMASS_SUPPORT := preload("res://game/presentation/office_floor/biomass_support.gd")
@export var floor_biomass_baked := false

const FLOOR_OFFSET := 0.002
## Floor height when nothing is found below a settling piece (planner floor).
const SETTLE_FLOOR := 0.0135
const SETTLE_SECONDS := 0.4
## Floor mass re-reads the walls round it this often, for this long after it appears.
const FLOOR_RECHECK_STEP := 1500
const FLOOR_RECHECK_SPAN := 15000
## Mass on an object looks again at what stands behind it this often (a pane breaks, a prop falls apart).
const SUPPORT_RECHECK_STEP := 3000
## Relief left on settled mass: it is pressed into the floor, not a heap.
const BAKED_DEPTH := 0.25
## Fits that are not caused by a move (first fit, periodic re-read) are spread out:
## each costs hundreds of rays, and all pieces of a level share one birth time.
const FITS_PER_FRAME := 1
## Periodic re-reads (nothing moved) only run on every Nth frame.
const RECHECK_FRAME_GAP := 6
static var _fit_frame := -1
static var _fit_count := 0

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
var _last_decal_transform := Transform3D()
var _impact_audio := IMPACT_AUDIO.new()
var _anchor_seen := false
var _clip_stamp: Array = []
var _clip_fit: Dictionary = {}
var _depth_scale := 1.0
var _level_bounds := Rect2()
var _born_msec := Time.get_ticks_msec()
var _last_fit_msec := 0


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
	_last_decal_transform = global_transform
	_anchor_seen = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	configure_projection(anchor)


func configure_world(_container: Node3D, impacts: Node) -> void:
	_projection_pool = impacts


## The floor the level stands on (world_bindings): biomass never spreads past its edge.
func configure_floor_debris(floor_view: Node3D) -> void:
	if floor_view == null or not floor_view.get("floor_size") is Vector2:
		return
	var size: Vector2 = floor_view.get("floor_size")
	var centre := Vector2(floor_view.global_position.x, floor_view.global_position.z)
	_level_bounds = Rect2(centre - size * 0.5, size)
	_restyle()


func configure_projection(anchor: Node3D) -> void:
	_impact_audio.bind(anchor, self)
	var previous: Node3D = _projection_anchor.get_ref() if _projection_anchor != null else null
	_projection_dirty = _projection_dirty or previous != anchor
	_projection_anchor = weakref(anchor) if anchor != null else null
	if anchor == null and previous != null and _visual != null:
		_rebuild()
	if _visual != null:
		_project_surface()


func _process(_delta: float) -> void:
	if _anchor == null:
		# Mass lying on the floor: fitted to the level and the walls round it.
		if BIOMASS.is_biomass_id(texture_name):
			_clip_biomass()
		else:
			set_process(false)
		return
	var anchor := _anchor.get_ref() as Node3D if _anchor != null else null
	var anchor_visible := anchor != null and anchor.is_visible_in_tree()
	if anchor_visible:
		_anchor_seen = true
	if _biomass_orphaned(anchor):
		_settle(_is_glass(anchor))
		return
	if anchor == null:
		if _visual != null:
			_visual.hide()
		set_process(false)
		return
	var anchor_transform := anchor.global_transform
	var decal_transform := global_transform
	if not anchor_transform.is_equal_approx(_last_anchor_transform):
		decal_transform = anchor_transform * _anchor_transform
		global_transform = decal_transform
		_last_decal_transform = decal_transform
	elif decal_transform != _last_decal_transform:
		_anchor_transform = anchor_transform.affine_inverse() * decal_transform
		_last_decal_transform = decal_transform
	_last_anchor_transform = anchor_transform
	if BIOMASS.is_biomass_id(texture_name):
		_clip_biomass()
	elif _projection_dirty or not decal_transform.is_equal_approx(_projection_transform) or not _visual.mesh is ArrayMesh or _receivers_changed():
		_project_surface()
	if _visual != null:
		_visual.visible = anchor_visible and not _biomass_hidden


static var _library: RefCounted
static var _library_green := false
var _visual: MeshInstance3D
var _fit: Node
var _fused := false
var _biomass_hidden := false


func _init() -> void:
	set_meta("blood_effect", true)


func _ready() -> void:
	_rebuild()
	if BIOMASS.is_biomass_id(texture_name):
		AMBIENT_SOUNDS.tag_events(self, [&"biomass_gurgle"])
	set_process(not floor_biomass_baked and (_anchor != null or BIOMASS.is_biomass_id(texture_name)))


func _exit_tree() -> void:
	_impact_audio.unregister()


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
	if floor_biomass_baked:
		set_process(false)
		return
	set_meta("planning_wall_mount", surface == "wall")
	set_meta("planning_free_place", true)
	if _visual != null:
		_visual.queue_free()
	if BIOMASS.is_biomass_id(texture_name):
		_rebuild_biomass()
		return
	remove_meta("biomass_piece")
	if _fit != null:
		_fit.queue_free()
		_fit = null
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
	# 3D materials ignore an AtlasTexture's region and draw the whole atlas, so sample the cell through the UV transform.
	var albedo := entry.get("texture") as Texture2D
	if albedo is AtlasTexture:
		var atlas := albedo as AtlasTexture
		var atlas_size := atlas.atlas.get_size()
		material.uv1_scale = Vector3(atlas.region.size.x / atlas_size.x, atlas.region.size.y / atlas_size.y, 1.0)
		material.uv1_offset = Vector3(atlas.region.position.x / atlas_size.x, atlas.region.position.y / atlas_size.y, 0.0)
		albedo = atlas.atlas
	material.albedo_texture = albedo
	material.normal_enabled = entry.get("normal") != null
	material.normal_texture = entry.get("normal")
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = float(entry.get("roughness", 0.35))
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
	if texture_id.begins_with("surface:"):
		return SURFACE_DECOR.texture_entry(texture_id)
	if _library == null or _library_green != BLOOD_LEVEL.forced_green:
		_library = LIBRARY.new()
		_library_green = BLOOD_LEVEL.forced_green
		# A platform with green blood draws placed decals with the same procedural frames the game uses.
		_library.call("load_assets", 512, 1.18, BLOOD_LEVEL.forced_green, BLOOD_LEVEL.color()) if BLOOD_LEVEL.forced_green else _library.call("load_assets")
	var category := texture_id.get_slice("_", 0)
	var variant := int(texture_id.get_slice("_", 1))
	# Layouts saved before the atlases may name a variant the category no
	# longer has (pool had nine images, its atlas has eight frames).
	var count: int = LIBRARY.frame_count(category)
	if count > 0 and variant > count:
		variant = posmod(variant - 1, count) + 1
	for entry: Dictionary in (_library.get("entries") as Dictionary).get(category, []):
		if int(entry.variant) == variant:
			return entry
	return {}


# Every texture the planner can place, as ids.
static func texture_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for category: String in LIBRARY.CATEGORIES:
		for variant in range(1, LIBRARY.frame_count(category) + 1):
			ids.append("%s_%02d" % [category, variant])
	return ids


func _project_surface() -> void:
	if BIOMASS.is_biomass_id(texture_name):
		_clip_biomass()
		return
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


# Volumetric biomass (ADR-0061): a relief patch that rises off the surface and
# fuses with touching biomass pieces through its BiomassFit child.
func _rebuild_biomass() -> void:
	set_meta("biomass_piece", true)
	_footprint = BIOMASS.FOOTPRINT
	_visual = MeshInstance3D.new()
	_visual.name = "BloodQuad"
	_visual.set_meta("surface_mark", true)
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.mesh = BIOMASS_MESH.cell_patch(BIOMASS.cell_of(texture_name))
	_fused = false
	_clip_stamp = []
	_clip_fit = {}
	_apply_surface()
	add_child(_visual)
	_restyle()
	set_process(true)
	if _fit == null:
		_fit = BIOMASS_FIT.new()
		_fit.name = "BiomassFit"
		add_child(_fit)
	else:
		_fit.call("show_own_relief")


func biomass_cell() -> int:
	return BIOMASS.cell_of(texture_name)


# World transform of the patch's own plane (x right, y up, z out of the surface).
func biomass_frame() -> Transform3D:
	return _visual.global_transform


func biomass_excluded() -> bool:
	return _visual == null or not is_visible_in_tree()


func biomass_show_cell() -> void:
	if _visual == null:
		return
	if _fused:
		_visual.mesh = BIOMASS_MESH.cell_patch(biomass_cell())
		_fused = false
		_clip_stamp = []
		_restyle()
	_biomass_hidden = false
	_visual.visible = true


func biomass_show_fused(mesh: Mesh) -> void:
	if _visual == null:
		return
	_visual.mesh = mesh
	_biomass_hidden = false
	_visual.visible = true
	_fused = true
	_clip_stamp = []
	_restyle()


func biomass_hide() -> void:
	_biomass_hidden = true
	if _visual != null:
		_visual.visible = false


# Fits the patch to the face it lies on: clipped at the edges, wrapped round
# convex ones; on the floor, folded up the walls round it. Recomputed only when
# the patch or its receiver moved (floor mass also during the first seconds,
# while the level around it is still being built).
func _clip_biomass() -> void:
	if _visual == null or not _visual.is_inside_tree():
		return
	var anchor := _anchor.get_ref() as Node3D if _anchor != null else null
	var floor_mass := anchor == null and surface == "floor"
	var now := Time.get_ticks_msec()
	var recheck := (floor_mass and now - _born_msec < FLOOR_RECHECK_SPAN and now - _last_fit_msec > FLOOR_RECHECK_STEP) or (anchor != null and now - _last_fit_msec > SUPPORT_RECHECK_STEP + int(absi(get_instance_id()) % 400))
	var visual_transform := _visual.global_transform
	var anchor_transform := anchor.global_transform if anchor != null else Transform3D()
	var mesh := _visual.mesh
	var unchanged: bool = not _clip_stamp.is_empty() and visual_transform.is_equal_approx(_clip_stamp[0]) and anchor_transform.is_equal_approx(_clip_stamp[1]) and anchor == _clip_stamp[2] and mesh == _clip_stamp[3]
	if unchanged and not recheck:
		return
	if unchanged or _clip_stamp.is_empty():
		var frame := Engine.get_process_frames()
		if frame != _fit_frame:
			_fit_frame = frame
			_fit_count = 0
		if _fit_count >= FITS_PER_FRAME or (unchanged and frame % RECHECK_FRAME_GAP != 0):
			return
		_fit_count += 1
	_clip_stamp = [visual_transform, anchor_transform, anchor, mesh]
	_last_fit_msec = now
	var space := get_world_3d().direct_space_state
	if anchor != null:
		_clip_fit = BIOMASS_CLIP.compute(_visual.global_transform, anchor, space)
		_clip_fit.merge(BIOMASS_SUPPORT.sample(_visual.global_transform, _local_rect(), space))
	elif floor_mass:
		_clip_fit = BIOMASS_CLIP.compute_floor(_visual.global_transform, _local_rect(), space)
	else:
		_clip_fit = {}
	_restyle()


# The patch, or the fused group it draws, in local units.
func _local_rect() -> Rect2:
	if _fused and _visual.mesh is ArrayMesh:
		var box := (_visual.mesh as ArrayMesh).custom_aabb
		return Rect2(box.position.x, box.position.y, box.size.x, box.size.y)
	return Rect2(-BIOMASS.FOOTPRINT * 0.5, BIOMASS.FOOTPRINT)


func _restyle() -> void:
	if _visual != null and BIOMASS.is_biomass_id(texture_name):
		BIOMASS_CLIP.style(_visual, _clip_fit, BIOMASS_CLIP.world_clip(_level_bounds), _depth_scale)


# The receiver was destroyed (freed, or its mesh hidden like broken glass).
# The planner keeps its own rules, so nothing settles while it is open.
func _biomass_orphaned(anchor: Node3D) -> bool:
	if _anchor == null or not BIOMASS.is_biomass_id(texture_name) or _visual == null or Engine.get_meta("planning_active", false):
		return false
	return anchor == null or anchor.is_queued_for_deletion() or (_anchor_seen and not anchor.is_visible_in_tree())


func _is_glass(anchor: Node3D) -> bool:
	var node := anchor
	while node != null and node != get_parent():
		if "glass" in str(node.name).to_lower():
			return true
		node = node.get_parent()
	return false


# Mass whose receiver is gone drops to the floor, lies flat there and fuses
# with other floor biomass. Broken glass leaves it as a loose heap; any other
# object presses it into the floor (shallow relief, shared with fusion).
func _settle(glass: bool) -> void:
	var start := global_transform
	_anchor = null
	configure_blood_attachment({})
	_projection_anchor = null
	_impact_audio.unregister()
	var ray := PhysicsRayQueryParameters3D.create(start.origin, start.origin + Vector3.DOWN * 30.0, 7)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	var floor_y: float = hit["position"].y if not hit.is_empty() and hit["normal"].y > .75 else SETTLE_FLOOR
	var yaw := float(absi(hash(start.origin)) % 628) / 100.0
	var end := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * maxf(start.basis.x.length(), 0.001)), Vector3(start.origin.x, floor_y, start.origin.z))
	configure_blood(texture_name, "floor")
	_last_fit_msec = 0
	_born_msec = Time.get_ticks_msec()
	set_meta("biomass_settled", "fallen" if glass else "baked")
	var flat := 1.0 if glass else BAKED_DEPTH
	var fall := func(amount: float) -> void:
		global_transform = start.interpolate_with(end, amount)
		_depth_scale = lerpf(1.0, flat, amount)
		_restyle()
	fall.call(0.0)
	create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN).tween_method(fall, 0.0, 1.0, SETTLE_SECONDS)


## Authored floor cells stay serializable, but have no visuals or callbacks in play.
func set_floor_biomass_baked(enabled: bool) -> void:
	if not BIOMASS.is_biomass_id(texture_name) or surface != "floor" or not attachment_owner.is_empty() or absf(rotation_degrees.x) > 0.01 or absf(rotation_degrees.z) > 0.01:
		return
	if floor_biomass_baked == enabled: return
	floor_biomass_baked = enabled
	if _fit != null:
		_fit.free()
		_fit = null
	if _visual != null:
		_visual.free()
		_visual = null
	if enabled:
		set_process(false)
	else:
		_rebuild()
