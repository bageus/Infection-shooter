extends StaticBody3D
## Debris pieces that have come to rest and been left alone. All of them draw as
## one MultiMesh; each keeps a small box on physics layer 4 so a bullet or a
## melee hit knocks that one piece out of the batch. Presentation only.

const CAPACITY := 256
const HIT_LAYER := 4
const HIT_RADIUS := 0.5

var _multimesh: MultiMesh
var _pieces: Array[Dictionary] = []


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
func add(piece_transform: Transform3D, size: Vector3, tint: Color) -> bool:
	if _pieces.size() >= CAPACITY:
		return false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = piece_transform.origin
	shape.basis = piece_transform.basis.orthonormalized()
	add_child(shape)
	var index := _pieces.size()
	_pieces.append({"transform": piece_transform, "tint": tint, "shape": shape})
	_multimesh.set_instance_transform(index, piece_transform)
	_multimesh.set_instance_color(index, tint)
	_multimesh.visible_instance_count = _pieces.size()
	return true


func count() -> int:
	return _pieces.size()


func get_projectile_material(_shape_index: int = -1) -> String:
	return "light"


func take_projectile_hit(_damage: float, hit_position: Vector3, _normal: Vector3, _direction: Vector3, _weapon: String) -> bool:
	_knock_out_nearest(hit_position)
	return false


func take_melee_hit(damage: float, hit_position: Vector3, direction: Vector3) -> void:
	take_projectile_hit(damage, hit_position, Vector3.ZERO, direction, "MELEE")


# Removes the piece nearest to the hit: the last piece takes its place in the
# batch, and the removed piece's box is disabled and freed.
func _knock_out_nearest(hit_position: Vector3) -> void:
	var nearest := -1
	var best := HIT_RADIUS
	for index in _pieces.size():
		var distance := (_pieces[index]["transform"] as Transform3D).origin.distance_to(hit_position)
		if distance <= best:
			best = distance
			nearest = index
	if nearest < 0:
		return
	var shape: CollisionShape3D = _pieces[nearest]["shape"]
	shape.set_deferred("disabled", true)
	shape.queue_free()
	var last := _pieces.size() - 1
	if nearest != last:
		var moved: Dictionary = _pieces[last]
		_pieces[nearest] = moved
		_multimesh.set_instance_transform(nearest, moved["transform"])
		_multimesh.set_instance_color(nearest, moved["tint"])
	_pieces.pop_back()
	_multimesh.visible_instance_count = _pieces.size()
