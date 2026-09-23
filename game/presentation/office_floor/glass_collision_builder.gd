extends Node3D

@export var glass_body_path: NodePath = NodePath("GlassBody")
@export var visual_path: NodePath = NodePath("Visual")


func _ready() -> void:
	call_deferred("_build_glass_collision")


func _build_glass_collision() -> void:
	var body := get_parent().get_node_or_null(glass_body_path) as StaticBody3D
	var visual := get_parent().get_node_or_null(visual_path) as Node3D
	if body == null or visual == null:
		return
	for child in body.get_children():
		if child is CollisionShape3D:
			child.queue_free()
	_add_glass_meshes(visual, body)


func _add_glass_meshes(node: Node, body: StaticBody3D) -> void:
	if node is MeshInstance3D and "glass" in node.name.to_lower():
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var shape := mesh_instance.mesh.create_trimesh_shape()
			if shape != null:
				var collision := CollisionShape3D.new()
				collision.shape = shape
				body.add_child(collision)
				collision.global_transform = mesh_instance.global_transform
	for child in node.get_children():
		_add_glass_meshes(child, body)
