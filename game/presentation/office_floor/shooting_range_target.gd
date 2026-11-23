extends Node3D
## Shooting range target: a hit drops the post and face flat on a hinge at the rear base edge,
## the base stays put, and the target stands up again after 10 seconds.

const MODEL_SCENE := preload("res://models/objects/enviroments/13/Shooting_Range_Target_30tris.glb")
const FALL_SECONDS := 0.25
const DOWN_SECONDS := 10.0
const RISE_SECONDS := 0.8
## The post hinges on its rear base edge at half its thickness (metres), so it lies on the floor when down.
const PIVOT := Vector3(0.0, 0.055, -0.22)
## Moves the post from the base centre to the rear edge, clear of the base when it falls.
const SHIFT_TO_REAR := Vector3(0.0, 0.0, -0.24)
const MIN_SIZE := 0.04

var model_path := "res://models/objects/enviroments/13/Shooting_Range_Target_30tris.glb"
var _hinge: AnimatableBody3D
var _axis := Vector3.RIGHT
var _fall := 0.0
var _down := false
var _tween: Tween


func _ready() -> void:
	var visual := MODEL_SCENE.instantiate() as Node3D
	add_child(visual)
	_hinge = AnimatableBody3D.new()
	_hinge.name = "Hinge"
	_hinge.transform = Transform3D(Basis(), PIVOT)
	add_child(_hinge)
	var moving: Array[MeshInstance3D] = []
	for part_name in ["Upright", "Target"]:
		var part := visual.find_child(part_name, true, false) as MeshInstance3D
		part.reparent(_hinge, true)
		part.position += SHIFT_TO_REAR
		moving.append(part)
	for part in moving:
		_add_box(_hinge, _box_in(_hinge, part))
	var base_body := StaticBody3D.new()
	base_body.name = "Base"
	add_child(base_body)
	var base := visual.find_child("Base", true, false) as MeshInstance3D
	_add_box(base_body, _box_in(base_body, base))


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


func _start_rise() -> void:
	_down = false


func _set_fall(amount: float) -> void:
	_fall = amount
	_hinge.transform = Transform3D(Basis(_axis, amount * PI * 0.5), PIVOT)


## The mesh's bounds in the frame of `body`, so collision boxes match the visible parts.
func _box_in(body: Node3D, mesh: MeshInstance3D) -> AABB:
	return body.global_transform.affine_inverse() * (mesh.global_transform * mesh.get_aabb())


func _add_box(body: Node3D, box: AABB) -> void:
	var shape := BoxShape3D.new()
	# Zero-thickness parts (the face plane) still need a solid box for bullets to hit.
	shape.size = Vector3(maxf(box.size.x, MIN_SIZE), maxf(box.size.y, MIN_SIZE), maxf(box.size.z, MIN_SIZE))
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = box.get_center()
	body.add_child(collision)
