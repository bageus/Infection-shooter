extends Area3D
## Local broad phase only; original actor-origin/health rules remain exact.
func _ready() -> void:
	collision_layer = 0
	collision_mask = 7
	monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.3, 4.4, 2.3)
	shape.shape = box
	add_child(shape)

func occupied(frame: Node3D) -> bool:
	for body in get_overlapping_bodies():
		if not body.is_in_group("player") and not body.is_in_group("infected"):
			continue
		if float(body.get("health")) <= 0.0:
			continue
		var local := frame.to_local(body.global_position)
		if absf(local.x) < 1.15 and absf(local.z) < 1.15 and absf(local.y) < 2.2:
			return true
	return false
