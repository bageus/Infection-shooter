extends Node3D

const TILE_SCENE := preload("res://game/presentation/office_floor/public/structural/base_floor_tile.tscn")
const TILE_MATERIAL := preload("res://game/presentation/office_floor/floor_tile_material.tres")
const MATERIAL_VARIANTS := 8
const SECTION_TILES := 8

@export var floor_size := Vector2(80.0, 60.0)
@export var tile_step := 2.0
@export var tile_y := 0.001
var openings: Array[Rect2] = []
var _batches: Dictionary = {}
var _tile_mesh: Mesh
var _materials: Array[StandardMaterial3D] = []
var _small_materials: Array[StandardMaterial3D] = []

func _ready() -> void:
	_build_tiles()

func _build_tiles() -> void:
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
				_add_tile(tile_position, 1.0)
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
						_add_tile(center, 0.25)

	_flush_batches()


func _add_tile(center: Vector2, tile_scale: float) -> void:
	# Partition by location and material so camera culling stays local.
	var cell := Vector2i(floori((center.x + floor_size.x * 0.5) / tile_step), floori((center.y + floor_size.y * 0.5) / tile_step))
	var variant := posmod(hash(cell), MATERIAL_VARIANTS)
	var key := Vector4i(floori(float(cell.x) / SECTION_TILES), floori(float(cell.y) / SECTION_TILES), variant, int(tile_scale < 1.0))
	if not _batches.has(key):
		_batches[key] = []
	var tile_transform := Transform3D(Basis.from_scale(Vector3(tile_scale, 1.0, tile_scale)), Vector3(center.x, tile_y, center.y))
	_batches[key].append(tile_transform)


func _flush_batches() -> void:
	for key: Vector4i in _batches:
		var transforms: Array = _batches[key]
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = _tile_mesh
		instances.instance_count = transforms.size()
		for index in transforms.size():
			instances.set_instance_transform(index, transforms[index])
		var section := MultiMeshInstance3D.new()
		section.name = "FloorSection_%d_%d_%d_%d" % [key.x, key.y, key.z, key.w]
		section.multimesh = instances
		section.material_override = _small_materials[key.z] if key.w == 1 else _materials[key.z]
		add_child(section)
	_batches.clear()


func _build_materials() -> void:
	for index in MATERIAL_VARIANTS:
		# Shallow copies share the generated textures across the entire floor.
		var material := TILE_MATERIAL.duplicate(false) as StandardMaterial3D
		var tint := 0.97 + float(index) * (0.06 / float(MATERIAL_VARIANTS - 1))
		material.albedo_color = Color(0.56 * tint, 0.59 * tint, 0.61 * tint, 1.0)
		material.roughness = TILE_MATERIAL.roughness + (float(index) - float(MATERIAL_VARIANTS - 1) * 0.5) * 0.006
		material.uv1_offset = Vector3(float(index % 4) * 0.25, float(floori(float(index) / 4.0)) * 0.5, 0.0)
		_materials.append(material)
		var small_material := material.duplicate(false) as StandardMaterial3D
		small_material.uv1_scale = Vector3(0.25, 0.25, 1.0)
		_small_materials.append(small_material)


func set_stair_openings(areas: Array[Rect2]) -> void:
	if openings == areas:
		return
	openings = areas.duplicate()
	_build_tiles()
