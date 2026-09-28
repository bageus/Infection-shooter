extends Node3D

@export var glass_body_path: NodePath = NodePath("GlassBody")
@export var visual_path: NodePath = NodePath("Visual")
@export var solid_window_collision := false


func _ready() -> void:
	call_deferred("_build_glass_collision")


func _build_glass_collision() -> void:
	var body := get_parent().get_node_or_null(glass_body_path) as StaticBody3D
	var visual := get_parent().get_node_or_null(visual_path) as Node3D
	if body == null or visual == null:
		return
	var exterior_window := solid_window_collision or visual.scene_file_path.get_file() == "01_window_double.glb" or get_parent().scene_file_path.get_file() == "window_double.tscn"
	if exterior_window:
		body.set("unbreakable", true)
	for child in body.get_children():
		if child is CollisionShape3D:
			child.queue_free()
	_add_glass_meshes(visual, body)
	if exterior_window:
		_add_window_barrier(visual, body)


func _add_window_barrier(visual: Node3D, body: StaticBody3D) -> void:
	var frame := visual.find_child("frame", true, false) as MeshInstance3D
	if frame == null or frame.mesh == null:
		return
	var bounds := frame.get_aabb()
	var box := BoxShape3D.new()
	# Fill the entire fixed exterior module, including the gaps between frame bars.
	box.size = Vector3(maxf(bounds.size.x + 0.24, 2.4), maxf(bounds.size.y, 0.24), maxf(bounds.size.z, 2.6))
	var collision := CollisionShape3D.new()
	collision.name = "ExteriorWindowBarrier"
	collision.shape = box
	body.add_child(collision)
	var frame_to_body := body.global_transform.affine_inverse() * frame.global_transform
	collision.transform = frame_to_body
	collision.position += frame_to_body.basis * bounds.get_center()


func _add_glass_meshes(node: Node, body: StaticBody3D) -> void:
	if node is MeshInstance3D and "glass" in node.name.to_lower():
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null and mesh_instance.is_visible_in_tree() and absf(mesh_instance.global_basis.determinant()) > 0.000000000001:
			var bounds := mesh_instance.get_aabb()
			var box := BoxShape3D.new()
			box.size = Vector3(maxf(bounds.size.x, 0.055), maxf(bounds.size.y, 0.055), maxf(bounds.size.z, 0.055))
			var collision := CollisionShape3D.new()
			collision.shape = box
			body.add_child(collision)
			collision.global_transform = mesh_instance.global_transform
			collision.position += collision.basis * bounds.get_center()
	for child in node.get_children():
		_add_glass_meshes(child, body)
