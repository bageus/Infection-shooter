@tool
extends Node3D

@export var visual_path: NodePath = NodePath("Visual")
@export var body_path: NodePath = NodePath("Body")
@export var rebuild_in_editor: bool = true
@export var exclude_name_tokens: PackedStringArray = PackedStringArray()
@export var use_simple_collision: bool = true

var _built := false


func _ready() -> void:
	call_deferred("_rebuild_collision")


func _rebuild_collision() -> void:
	if _built:
		return
	var visual := get_node_or_null(visual_path) as Node3D
	var body := get_node_or_null(body_path) as CollisionObject3D
	if visual == null or body == null:
		return
	for child in body.get_children():
		if child is CollisionShape3D:
			child.queue_free()
	_add_mesh_collisions(visual, body)
	_built = true


func _add_mesh_collisions(node: Node, body: CollisionObject3D) -> void:
	if _is_excluded(node):
		return
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var shape: Shape3D
			if use_simple_collision:
				var box := BoxShape3D.new()
				box.size = mesh_instance.get_aabb().size
				shape = box
			else:
				shape = mesh_instance.mesh.create_trimesh_shape()
			if shape != null:
				var collision := CollisionShape3D.new()
				collision.shape = shape
				body.add_child(collision)
				if use_simple_collision:
					var aabb := mesh_instance.get_aabb()
					var mesh_to_body: Transform3D = body.global_transform.affine_inverse() * mesh_instance.global_transform
					collision.transform = mesh_to_body
					collision.position += mesh_to_body.basis * aabb.get_center()
				else:
					collision.global_transform = mesh_instance.global_transform
	for child in node.get_children():
		_add_mesh_collisions(child, body)


func _is_excluded(node: Node) -> bool:
	var lower := node.name.to_lower()
	for token in exclude_name_tokens:
		if str(token).to_lower() in lower:
			return true
	return false
