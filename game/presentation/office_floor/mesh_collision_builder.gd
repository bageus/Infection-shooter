@tool
extends Node3D

@export var visual_path: NodePath = NodePath("Visual")
@export var body_path: NodePath = NodePath("Body")
@export var rebuild_in_editor: bool = true
@export var exclude_name_tokens: PackedStringArray = PackedStringArray()
@export var use_simple_collision: bool = true
@export var breakaway_frame_surface: int = -1
@export var frame_surface_boxes := false

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
	if body is RigidBody3D:
		# Make visual a child first, then build collision in the body's local space.
		# This keeps mesh, shapes and rigid transform perfectly aligned.
		var visual_global := visual.global_transform
		visual.reparent(body, true)
		visual.global_transform = visual_global
	_add_mesh_collisions(visual, body)
	if body.get_child_count() == 1 and body is RigidBody3D:
		_add_fallback_collision(visual, body)
	_built = true


func _add_fallback_collision(visual: Node3D, body: CollisionObject3D) -> void:
	var merged := AABB()
	var found := false
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(visual, meshes)
	for mesh in meshes:
		var local_transform := body.global_transform.affine_inverse() * mesh.global_transform
		var aabb := local_transform * mesh.get_aabb()
		merged = aabb if not found else merged.merge(aabb)
		found = true
	if not found:
		return
	var box := BoxShape3D.new()
	box.size = merged.size
	var collision := CollisionShape3D.new()
	collision.shape = box
	collision.position = merged.get_center()
	body.add_child(collision)


func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and not _is_excluded(node) and absf((node as MeshInstance3D).global_basis.determinant()) > 0.000000000001:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, result)


func _add_mesh_collisions(node: Node, body: CollisionObject3D) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null and not _is_excluded(node) and mesh_instance.is_visible_in_tree() and absf(mesh_instance.global_basis.determinant()) > 0.000000000001:
			if frame_surface_boxes and "frame" in mesh_instance.name.to_lower():
				_add_frame_boxes(mesh_instance, body)
				return
			if not use_simple_collision and breakaway_frame_surface >= 0 and "frame" in mesh_instance.name.to_lower():
				_add_frame_surfaces(mesh_instance, body)
				return
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


func _add_frame_boxes(mesh_instance: MeshInstance3D, body: CollisionObject3D) -> void:
	var mesh_to_body := body.global_transform.affine_inverse() * mesh_instance.global_transform
	for surface in mesh_instance.mesh.get_surface_count():
		var arrays := mesh_instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			continue
		var bounds := AABB(vertices[0], Vector3.ZERO)
		for vertex in vertices:
			bounds = bounds.expand(vertex)
		var box := BoxShape3D.new()
		box.size = Vector3(maxf(bounds.size.x, 0.08), maxf(bounds.size.y, 0.08), maxf(bounds.size.z, 0.08))
		var collision := CollisionShape3D.new()
		collision.name = "FrameBar%d" % surface
		collision.shape = box
		body.add_child(collision)
		collision.transform = mesh_to_body
		collision.position += mesh_to_body.basis * bounds.get_center()


func _add_frame_surfaces(mesh_instance: MeshInstance3D, body: CollisionObject3D) -> void:
	for surface in mesh_instance.mesh.get_surface_count():
		var surface_mesh := ArrayMesh.new()
		surface_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_instance.mesh.surface_get_arrays(surface))
		var shape := surface_mesh.create_trimesh_shape()
		if shape == null:
			continue
		var collision := CollisionShape3D.new()
		collision.name = "BreakawayPanel" if surface == breakaway_frame_surface else "FrameCollision"
		collision.shape = shape
		body.add_child(collision)
		collision.global_transform = mesh_instance.global_transform


func _is_excluded(node: Node) -> bool:
	var lower := node.name.to_lower()
	for token in exclude_name_tokens:
		if str(token).to_lower() in lower:
			return true
	return false
