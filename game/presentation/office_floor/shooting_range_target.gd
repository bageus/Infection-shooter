extends StaticBody3D
## Shooting range target: a hit drops the post and face flat on a hinge at the rear base edge,
## the base stays put, and the target stands up again after 10 seconds.
## One static body: its post and face colliders move with the visual hinge, so nested moving bodies are not needed.

const MODEL_SCENE := preload("res://models/objects/enviroments/13/13_Shooting_Range_Target_30tris.glb")
const FALL_SECONDS := 0.25
const DOWN_SECONDS := 10.0
const RISE_SECONDS := 0.8
## The post hinges on its rear base edge at half its thickness (metres), so it lies on the floor when down.
const PIVOT := Vector3(0.0, 0.055, -0.22)
## Moves the post from the base centre to the rear edge, clear of the base when it falls.
const SHIFT_TO_REAR := Vector3(0.0, 0.0, -0.24)
const MIN_SIZE := 0.04

var model_path := "res://models/objects/enviroments/13/13_Shooting_Range_Target_30tris.glb"
var _hinge: Node3D
var _moving_shapes: Array[CollisionShape3D] = []
var _moving_offsets: Array[Transform3D] = []
var _axis := Vector3.RIGHT
var _fall := 0.0
var _down := false
var _tween: Tween


func _ready() -> void:
	var visual := MODEL_SCENE.instantiate() as Node3D
	add_child(visual)
	_hinge = Node3D.new()
	_hinge.name = "Hinge"
	add_child(_hinge)
	_hinge.transform = Transform3D(Basis(), PIVOT)
	for part_name in ["Upright", "Target"]:
		var part := visual.find_child(part_name, true, false) as MeshInstance3D
		part.reparent(_hinge, true)
		part.position += SHIFT_TO_REAR
	for part_name in ["Upright", "Target"]:
		_add_moving_box(_hinge.find_child(part_name, false, false) as MeshInstance3D)
	var base := visual.find_child("Base", true, false) as MeshInstance3D
	var base_box := _box_in(self, base)
	_add_box(base_box, Transform3D(Basis(), base_box.get_center()))
	_set_fall(0.0)


func take_projectile_hit(_damage: float, _hit_position: Vector3, _normal: Vector3, direction: Vector3, _weapon: String) -> bool:
	if _down:
		return true
	_down = true
	var away := Vector3(direction.x, 0.0, direction.z)
	# Fall away from the shooter: the top of the post moves along the shot direction.
	_axis = Vector3.UP.cross(away.normalized() if not away.is_zero_approx() else Vector3.FORWARD)
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_fall, _fall, 1.0, FALL_SECONDS)
	_tween.tween_interval(DOWN_SECONDS)
	_tween.tween_callback(_start_rise)
	_tween.tween_method(_set_fall, 1.0, 0.0, RISE_SECONDS)
	return true


func get_projectile_material(_shape_index: int = -1) -> String:
	return "metal"


func _start_rise() -> void:
	_down = false


func _set_fall(amount: float) -> void:
	_fall = amount
	var hinge_transform := Transform3D(Basis(_axis, amount * PI * 0.5), PIVOT)
	_hinge.transform = hinge_transform
	for index in _moving_shapes.size():
		_moving_shapes[index].transform = hinge_transform * _moving_offsets[index]


## The mesh's bounds in the frame of `body`, so collision boxes match the visible parts.
func _box_in(body: Node3D, mesh: MeshInstance3D) -> AABB:
	return body.global_transform.affine_inverse() * (mesh.global_transform * mesh.get_aabb())


func _add_moving_box(mesh: MeshInstance3D) -> void:
	var box := _box_in(_hinge, mesh)
	var offset := Transform3D(Basis(), box.get_center())
	_moving_offsets.append(offset)
	_moving_shapes.append(_add_box(box, offset))


func _add_box(box: AABB, offset: Transform3D) -> CollisionShape3D:
	var shape := BoxShape3D.new()
	# Zero-thickness parts (the face plane) still need a solid box for bullets to hit.
	shape.size = Vector3(maxf(box.size.x, MIN_SIZE), maxf(box.size.y, MIN_SIZE), maxf(box.size.z, MIN_SIZE))
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = offset
	add_child(collision)
	return collision
