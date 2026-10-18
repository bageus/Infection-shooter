extends Node3D

const TILE_SCENE := preload("res://game/presentation/office_floor/public/structural/base_floor_tile.tscn")
const TILE_MATERIAL := preload("res://game/presentation/office_floor/floor_tile_material.tres")
const MATERIAL_VARIANTS := 2
const SECTION_TILES := 4
const GLASS_BAKE := preload("res://game/presentation/office_floor/glass_floor_bake.gd")
const GLASS_SCATTER := preload("res://game/presentation/office_floor/glass_floor_scatter.gd")
const SURFACE_EVENTS := preload("res://game/presentation/office_floor/surface_decal_events.gd")
const SURFACE_SETTINGS := preload("res://game/presentation/office_floor/public/surface_decal_config.gd")
const MATERIAL_SCATTER := preload("res://game/presentation/office_floor/material_floor_scatter.gd")

@export var floor_size := Vector2(80.0, 60.0)
@export var tile_step := 2.0
@export var tile_y := 0.001
var openings: Array[Rect2] = []
var _batches: Dictionary = {}
var _tile_mesh: Mesh
var _materials: Array[ShaderMaterial] = []
var _sections: Dictionary = {}
@export var surface_decals: Dictionary = {}
var _surface_events := SURFACE_EVENTS.new()
var _glass := GLASS_BAKE.new(_set_glass_texture)

func _ready() -> void:
	_build_tiles()
	_glass.prepare()
	_surface_events.configure(self, _glass._atlases)
	configure_surface_decals(surface_decals)
	set_process(false)


func _process(_delta: float) -> void:
	var floor_pending := _glass.step()
	var surface_pending := _surface_events.receivers.step()
	set_process(floor_pending or surface_pending)

func _build_tiles() -> void:
	clear_glass_debris()
	_glass.origin = -floor_size * 0.5
	_sections.clear()
	_glass.valid_cells.clear()
	if _materials.is_empty():
		_build_materials()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_batches.clear()
	if _tile_mesh == null:
		var tile := TILE_SCENE.instantiate() as MeshInstance3D
		_tile_mesh = tile.mesh
		tile.free()
	var columns := ceili(floor_size.x / tile_step)
	var rows := ceili(floor_size.y / tile_step)
	var start_x := -floor_size.x * 0.5 + tile_step * 0.5
	var start_z := -floor_size.y * 0.5 + tile_step * 0.5
	for z in rows:
		for x in columns:
			var tile_position := Vector2(start_x + x * tile_step, start_z + z * tile_step)
			var tile_area := Rect2(tile_position - Vector2.ONE * tile_step * 0.5, Vector2.ONE * tile_step)
			var intersects_opening := false
			for opening in openings:
				if opening.intersects(tile_area):
					intersects_opening = true
					break
			if not intersects_opening:
				_add_tile(tile_position, 1.0, Vector2.ZERO)
				continue
			for sub_z in 4:
				for sub_x in 4:
					var center := tile_area.position + Vector2(sub_x + 0.5, sub_z + 0.5) * (tile_step / 4.0)
					var covered := false
					for opening in openings:
						if opening.has_point(center):
							covered = true
							break
					if not covered:
						_add_tile(center, 0.25, center - tile_position)

	_flush_batches()


func _add_tile(center: Vector2, tile_scale: float, tile_offset: Vector2) -> void:
	# Partition by location and material so camera culling stays local.
	var cell := Vector2i(floori((center.x + floor_size.x * 0.5) / tile_step), floori((center.y + floor_size.y * 0.5) / tile_step))
	var variant := posmod(hash(cell), MATERIAL_VARIANTS)
	var key := Vector4i(floori(float(cell.x) / SECTION_TILES), floori(float(cell.y) / SECTION_TILES), variant, int(tile_scale < 1.0))
	if not _batches.has(key):
		_batches[key] = []
	var tile_transform := Transform3D(Basis.from_scale(Vector3(tile_scale, 1.0, tile_scale)), Vector3(center.x, tile_y, center.y))
	# The shader draws seams in parent-tile space, so subtiles keep the 2 m grid.
	_batches[key].append([tile_transform, Color(tile_offset.x, tile_offset.y, tile_scale, 0.0)])


func _flush_batches() -> void:
	for key: Vector4i in _batches:
		var transforms: Array = _batches[key]
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.use_custom_data = true
		instances.mesh = _tile_mesh
		instances.instance_count = transforms.size()
		for index in transforms.size():
			instances.set_instance_transform(index, transforms[index][0])
			instances.set_instance_custom_data(index, transforms[index][1])
		var section := MultiMeshInstance3D.new()
		section.name = "FloorSection_%d_%d_%d_%d" % [key.x, key.y, key.z, key.w]
		section.multimesh = instances
		section.material_override = _materials[key.z]
		add_child(section)
		var cell := Vector2i(key.x, key.y)
		if not _sections.has(cell):
			_sections[cell] = []
		_sections[cell].append({"node": section, "material": _materials[key.z]})
		_glass.valid_cells[cell] = true
	_batches.clear()


func _build_materials() -> void:
	for index in MATERIAL_VARIANTS:
		# Shallow copies share the generated textures across the entire floor.
		var material := TILE_MATERIAL.duplicate(false) as ShaderMaterial
		material.set_shader_parameter("tint", 0.99 + float(index) * (0.02 / float(MATERIAL_VARIANTS - 1)))
		material.set_shader_parameter("roughness_offset", (float(index) - float(MATERIAL_VARIANTS - 1) * 0.5) * 0.006)
		_materials.append(material)


func set_stair_openings(areas: Array[Rect2]) -> void:
	if openings == areas:
		return
	openings = areas.duplicate()
	_build_tiles()


func scatter_glass_debris(panes: Array[MeshInstance3D], direction: Vector3) -> void:
	GLASS_SCATTER.scatter(self, panes, direction)


func stamp_glass_debris(at: Vector2, frame: int, size: float, turns: int = 0) -> bool:
	return stamp_material_debris(at, "glass", frame, size, turns)


func scatter_prop_debris(at: Vector3, footprint: Vector2, recipe: Array[String], direction: Vector3, excluded: Array[RID] = []) -> void:
	MATERIAL_SCATTER.scatter(self, at, footprint, recipe, direction, excluded)


func stamp_material_debris(at: Vector2, kind: String, frame: int, size: float, turns: int = 0) -> bool:
	if not at.is_finite() or not Rect2(-floor_size * 0.5, floor_size).has_point(at):
		return false
	for opening in openings:
		if opening.has_point(at):
			return false
	var config: Dictionary = _surface_events.settings.debris
	var accepted := _glass.stamp(at, frame, clampf(size * float(config.size), 0.25, 1.5), turns, kind, config.opacity)
	if accepted:
		set_process(true)
	return accepted


func clear_glass_debris() -> void:
	_glass.clear()
	_surface_events.clear()
	set_process(false)


func _set_glass_texture(cell: Vector2i, texture: Texture2D) -> void:
	for entry: Dictionary in _sections.get(cell, []):
		var section := entry.node as MultiMeshInstance3D
		if not is_instance_valid(section):
			continue
		if texture == null:
			section.material_override = entry.material
			continue
		var material := (entry.material as ShaderMaterial).duplicate(false) as ShaderMaterial
		material.set_shader_parameter("floor_damage", _glass.tiles[cell].layers.get(0, {}).get("texture", texture))
		material.set_shader_parameter("floor_scuff", _glass.tiles[cell].layers.get(1, {}).get("texture", texture))
		material.set_shader_parameter("has_floor_damage", _glass.tiles[cell].layers.has(0))
		material.set_shader_parameter("has_floor_scuff", _glass.tiles[cell].layers.has(1))
		material.set_shader_parameter("glass_debris", texture)
		material.set_shader_parameter("debris_roughness", _glass.tiles[cell].surface_texture)
		material.set_shader_parameter("glass_enabled", true)
		material.set_shader_parameter("glass_origin", _glass.origin + Vector2(cell) * GLASS_BAKE.METERS)
		material.set_shader_parameter("glass_world_to_floor", global_transform.affine_inverse())
		section.material_override = material


func configure_surface_decals(config: Dictionary) -> void:
	surface_decals = SURFACE_SETTINGS.normalized(config)
	_surface_events.settings = surface_decals

func get_surface_decals() -> Dictionary:
	return SURFACE_SETTINGS.normalized(surface_decals)

func stamp_floor_surface(at: Vector2, kind: String, frame: int, size: float, turns: int = 0) -> bool:
	if kind not in ["floor_damage", "floor_scuff", "bullet"] or not at.is_finite() or not Rect2(-floor_size * 0.5, floor_size).has_point(at): return false
	for opening in openings:
		if opening.has_point(at): return false
	var config: Dictionary = _surface_events.settings[kind]
	var ok := _glass.stamp(at, frame, clampf(size * float(config.size), 0.25, 1.5), turns, kind, config.opacity)
	if ok: set_process(true)
	return ok

func bake_surface_hit(collider: Node3D, point: Vector3, normal: Vector3, weapon: String, anchor: MeshInstance3D = null) -> bool:
	if collider.has_method("has_display") and collider.call("has_display"): return true
	return _surface_events.hit(collider, point, normal, weapon, anchor)

func bake_glass_hit(pane: Node3D, point: Vector3, normal: Vector3) -> bool:
	var target: MeshInstance3D
	var distance := INF
	for node: Node3D in pane.get("_glass_nodes"):
		if not node is MeshInstance3D or not node.is_visible_in_tree(): continue
		var bounds: AABB = node.global_transform * (node as MeshInstance3D).get_aabb()
		var d := point.distance_squared_to(point.clamp(bounds.position, bounds.end))
		if d < distance:
			distance = d
			target = node as MeshInstance3D
	return _surface_events.glass_hit(target, point, normal) if target != null else false

func bake_display_hit(prop: Node3D, point: Vector3, normal: Vector3) -> void:
	var display := prop.get("_display") as Node3D
	if not is_instance_valid(display) or not display.is_visible_in_tree(): return
	for screen: Dictionary in display.get("screens"):
		var mesh := screen.mesh as MeshInstance3D
		var bounds: AABB = mesh.global_transform * mesh.get_aabb()
		if point.distance_to(point.clamp(bounds.position, bounds.end)) < 0.2:
			_surface_events.glass_hit(mesh, point, normal)
			break

func bake_step(point: Vector3, normal: Vector3) -> void:
	_surface_events.step_at(point, normal)

func get_decal_preview(kind: String) -> Texture2D:
	var atlas_kind := "glass_fracture" if kind == "glass" else ("paper" if kind == "debris" else kind)
	var frames: Array = _glass._atlases.sources.get(atlas_kind, [])
	return ImageTexture.create_from_image(frames[0]) if not frames.is_empty() else null

func _exit_tree() -> void:
	_surface_events.clear()
