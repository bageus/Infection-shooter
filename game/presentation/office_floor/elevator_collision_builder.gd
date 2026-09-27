extends Node3D

func _ready() -> void:
	call_deferred("_build")

func _build() -> void:
	var body := get_node_or_null("Body") as StaticBody3D
	if body == null:
		return
	for child in body.get_children():
		if child is CollisionShape3D:
			child.queue_free()
	# The freight and passenger GLBs have different widths and offsets. Use their
	# actual shell meshes so the opening stays aligned with the visible doorway.
	if name == "ElevatorDoor":
		# The GLB combines both jambs and lintel in one mesh. A single AABB
		# across that mesh would seal the doorway even after the leaves slide.
		_add_box(body, Vector3(0.93, 3.0, 0.25), Vector3(-1.53, 1.5, 0))
		_add_box(body, Vector3(0.93, 3.0, 0.25), Vector3(1.53, 1.5, 0))
		_add_box(body, Vector3(2.13, 0.7, 0.25), Vector3(0, 2.65, 0))
	else:
		_add_shell(get_node_or_null("Visual"), body)


func _add_box(body: StaticBody3D, size: Vector3, local_position: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	collision.position = local_position
	body.add_child(collision)

func _add_shell(node: Node, body: StaticBody3D) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		var part := mesh.name.to_lower()
		if (part.begins_with("cabin_") or part.begins_with("front_")) and mesh.mesh != null:
			var bounds := mesh.get_aabb()
			var box := BoxShape3D.new()
			box.size = Vector3(maxf(bounds.size.x, 0.02), maxf(bounds.size.y, 0.02), maxf(bounds.size.z, 0.02))
			var collision := CollisionShape3D.new()
			collision.shape = box
			body.add_child(collision)
			var local := body.global_transform.affine_inverse() * mesh.global_transform
			collision.transform = local
			collision.position += local.basis * bounds.get_center()
	for child in node.get_children():
		_add_shell(child, body)
