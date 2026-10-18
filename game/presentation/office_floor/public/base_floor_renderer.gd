extends Node3D

const TILE_SCENE := preload("res://game/presentation/office_floor/public/structural/base_floor_tile.tscn")
const TILE_MATERIAL := preload("res://game/presentation/office_floor/floor_tile_material.tres")
const MATERIAL_VARIANTS := 2
const SECTION_TILES := 4
const GLASS_SURFACE := preload("res://game/presentation/office_floor/glass_footstep_surface.gd")
const GLASS_BAKE := preload("res://game/presentation/office_floor/glass_floor_bake.gd")
const GLASS_SCATTER := preload("res://game/presentation/office_floor/glass_floor_scatter.gd")
const MATERIAL_SCATTER := preload("res://game/presentation/office_floor/material_floor_scatter.gd")

@export var floor_size := Vector2(80.0, 60.0)
@export var tile_step := 2.0
@export var tile_y := 0.001
var openings: Array[Rect2] = []
var _batches: Dictionary = {}
var _tile_mesh: Mesh
var _materials: Array[ShaderMaterial] = []
var _sections: Dictionary = {}
var _glass := GLASS_BAKE.new(_set_glass_texture)

func _ready() -> void:
	_build_tiles()
	_glass.prepare()
	set_process(false)


func _process(_delta: float) -> void:
	set_process(_glass.step())

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
	var accepted := _glass.stamp(at, frame, size, turns, kind)
	if accepted:
		set_process(true)
	return accepted


func has_glass_at(world_position: Vector3) -> bool:
	return GLASS_SURFACE.has_glass_at(self, _glass, world_position)


func clear_glass_debris() -> void:
	_glass.clear()
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
		material.set_shader_parameter("glass_debris", texture)
		material.set_shader_parameter("debris_roughness", _glass.tiles[cell].surface_texture)
		material.set_shader_parameter("glass_enabled", true)
		material.set_shader_parameter("glass_origin", _glass.origin + Vector2(cell) * GLASS_BAKE.METERS)
		material.set_shader_parameter("glass_world_to_floor", global_transform.affine_inverse())
		section.material_override = material
