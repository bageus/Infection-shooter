extends Node3D

@export_file("*.glb") var model_path := ""


func _ready() -> void:
	if model_path.is_empty():
		return
	var packed := load(model_path) as PackedScene
	if packed == null:
		push_error("Environment model unavailable: " + model_path)
		return
	var visual := packed.instantiate() as Node3D
	if visual == null:
		return
	visual.name = "Visual"
	add_child(visual)
	var body := StaticBody3D.new()
	body.name = "Body"
	add_child(body)
	_add_shapes(visual, body)


func _add_shapes(node: Node, body: StaticBody3D) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		if mesh.mesh != null and mesh.is_visible_in_tree() and absf(mesh.global_basis.determinant()) > 0.000000000001:
			var box := BoxShape3D.new()
			var bounds := mesh.get_aabb()
			box.size = Vector3(maxf(bounds.size.x, 0.01), maxf(bounds.size.y, 0.01), maxf(bounds.size.z, 0.01))
			var shape := CollisionShape3D.new()
			shape.shape = box
			body.add_child(shape)
			var local := body.global_transform.affine_inverse() * mesh.global_transform
			shape.transform = local
			shape.position += local.basis * bounds.get_center()
	for child in node.get_children():
		_add_shapes(child, body)
