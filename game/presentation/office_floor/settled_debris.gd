extends StaticBody3D
## Debris pieces that have come to rest and been left alone. All of them draw as
## one MultiMesh. For hits, each 1 m grid cell has a single box on physics layer
## 4; a bullet or melee hit knocks out the nearest piece in that cell, so the
## shape count follows the floor area, not the piece count. Presentation only.

const CAPACITY := 256
const HIT_LAYER := 4
const HIT_RADIUS := 0.5
const CELL := 1.0
const CELL_PADDING := 0.2

var _multimesh: MultiMesh
var _pieces: Array[Dictionary] = []
var _cells: Dictionary = {}


func _ready() -> void:
	collision_layer = HIT_LAYER
	collision_mask = 0
	var cube := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.roughness = 0.9
	material.vertex_color_use_as_albedo = true
	cube.material = material
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.mesh = cube
	_multimesh.instance_count = CAPACITY
	_multimesh.visible_instance_count = 0
	var instance := MultiMeshInstance3D.new()
	instance.name = "SettledPieces"
	instance.multimesh = _multimesh
	add_child(instance)


# Returns false when the batch is full; the caller keeps the piece as it was.
func add(piece_transform: Transform3D, _size: Vector3, tint: Color) -> bool:
	if _pieces.size() >= CAPACITY:
		return false
	var origin := piece_transform.origin
	var cell := _cell_of(origin)
	var entry: Dictionary = _cells.get(cell, {})
	if entry.is_empty():
		entry = {"shape": _make_cell_shape(), "count": 0, "low": origin.y, "high": origin.y}
		add_child(entry["shape"])
		_cells[cell] = entry
	entry["count"] += 1
	entry["low"] = minf(entry["low"], origin.y)
	entry["high"] = maxf(entry["high"], origin.y)
	_fit_cell_shape(cell, entry)
	var index := _pieces.size()
	_pieces.append({"transform": piece_transform, "tint": tint, "cell": cell})
	_multimesh.set_instance_transform(index, piece_transform)
	_multimesh.set_instance_color(index, tint)
	_multimesh.visible_instance_count = _pieces.size()
	return true


func count() -> int:
	return _pieces.size()


func cell_count() -> int:
	return _cells.size()


func get_projectile_material(_shape_index: int = -1) -> String:
	return "light"


func take_projectile_hit(_damage: float, hit_position: Vector3, _normal: Vector3, _direction: Vector3, _weapon: String) -> bool:
	_knock_out_nearest(hit_position)
	return false


func take_melee_hit(damage: float, hit_position: Vector3, direction: Vector3) -> void:
	take_projectile_hit(damage, hit_position, Vector3.ZERO, direction, "MELEE")


func _cell_of(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / CELL), floori(point.z / CELL))


func _make_cell_shape() -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	return shape


# The cell box spans the cell's footprint and the height range of its pieces.
func _fit_cell_shape(cell: Vector2i, entry: Dictionary) -> void:
	var shape: CollisionShape3D = entry["shape"]
	var height: float = entry["high"] - entry["low"] + CELL_PADDING
	(shape.shape as BoxShape3D).size = Vector3(CELL, height, CELL)
	shape.position = Vector3((cell.x + 0.5) * CELL, (entry["low"] + entry["high"]) * 0.5, (cell.y + 0.5) * CELL)


# Removes the piece nearest the hit within its cell. The last piece takes its
# place in the batch. A cell whose last piece leaves loses its box.
func _knock_out_nearest(hit_position: Vector3) -> void:
	var cell := _cell_of(hit_position)
	var nearest := -1
	var best := HIT_RADIUS
	for index in _pieces.size():
		if _pieces[index]["cell"] != cell:
			continue
		var distance := (_pieces[index]["transform"] as Transform3D).origin.distance_to(hit_position)
		if distance <= best:
			best = distance
			nearest = index
	if nearest < 0:
		return
	var entry: Dictionary = _cells[cell]
	entry["count"] -= 1
	if entry["count"] == 0:
		var shape: CollisionShape3D = entry["shape"]
		shape.set_deferred("disabled", true)
		shape.queue_free()
		_cells.erase(cell)
	var last := _pieces.size() - 1
	if nearest != last:
		var moved: Dictionary = _pieces[last]
		_pieces[nearest] = moved
		_multimesh.set_instance_transform(nearest, moved["transform"])
		_multimesh.set_instance_color(nearest, moved["tint"])
	_pieces.pop_back()
	_multimesh.visible_instance_count = _pieces.size()
