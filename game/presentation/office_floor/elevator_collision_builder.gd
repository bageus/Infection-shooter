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
	# Instance names change in authored/saved layouts. Build from mesh geometry,
	# preserving the opening in the combined Wall mesh instead of spanning it.
	_add_shell(get_node_or_null("Visual"), body)

func _add_shell(node: Node, body: StaticBody3D) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		var part := mesh.name.to_lower()
		if part == "wall" and mesh.mesh != null:
			var collision := CollisionShape3D.new()
			collision.shape = mesh.mesh.create_trimesh_shape()
			body.add_child(collision)
			collision.global_transform = mesh.global_transform
		elif (part.begins_with("cabin_") or part.begins_with("front_")) and mesh.mesh != null:
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


# Public structural scene wiring v1, forwarded inside the owning scene only.
func configure_world(container: Node3D, impacts: Node) -> void:
	for child in get_children():
		if child.has_method("configure_world"):
			child.call("configure_world", container, impacts)


func configure_player(actor: Node3D) -> void:
	for child in get_children():
		if child.has_method("configure_player"):
			child.call("configure_player", actor)
