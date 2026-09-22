extends Node3D

@export var cabin_size := Vector3(3.4, 2.8, 3.2)
@export var doorway_width := 1.8
@export var wall_thickness := 0.16
@export var floor_thickness := 0.12

func _ready() -> void:
	call_deferred("_build")

func _build() -> void:
	var body := get_node_or_null("Body") as StaticBody3D
	if body == null:
		return
	for child in body.get_children():
		if child is CollisionShape3D:
			child.queue_free()
	var half_x := cabin_size.x * 0.5
	var half_z := cabin_size.z * 0.5
	var side_width := maxf(0.1, (cabin_size.x - doorway_width) * 0.5)
	_add_box(body, Vector3(cabin_size.x, floor_thickness, cabin_size.z), Vector3(0, -floor_thickness * 0.5, 0))
	_add_box(body, Vector3(cabin_size.x, cabin_size.y, wall_thickness), Vector3(0, cabin_size.y * 0.5, half_z))
	_add_box(body, Vector3(wall_thickness, cabin_size.y, cabin_size.z), Vector3(-half_x, cabin_size.y * 0.5, 0))
	_add_box(body, Vector3(wall_thickness, cabin_size.y, cabin_size.z), Vector3(half_x, cabin_size.y * 0.5, 0))
	_add_box(body, Vector3(side_width, cabin_size.y, wall_thickness), Vector3(-doorway_width * 0.5 - side_width * 0.5, cabin_size.y * 0.5, -half_z))
	_add_box(body, Vector3(side_width, cabin_size.y, wall_thickness), Vector3(doorway_width * 0.5 + side_width * 0.5, cabin_size.y * 0.5, -half_z))

func _add_box(body: StaticBody3D, size: Vector3, position: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = position
	body.add_child(collision)
