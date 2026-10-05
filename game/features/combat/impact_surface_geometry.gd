extends RefCounted
## Project a broad-phase collider hit onto the visible mesh, not its bounding box.
var faces: Dictionary = {}
var visuals: Dictionary = {}


func register(collider: Node3D, visual: Node3D) -> void:
	visuals[collider.get_instance_id()] = weakref(visual)



func resolve(collider: Node3D, point: Vector3, direction: Vector3) -> Dictionary:
	if not is_instance_valid(collider):
		return {}
	var meshes: Array[MeshInstance3D] = []
	if visuals.has(collider.get_instance_id()):
		var visual := (visuals[collider.get_instance_id()] as WeakRef).get_ref() as Node
		if visual != null:
			_collect(visual, meshes)
	_collect(collider, meshes)
	if meshes.is_empty():
		# Structural collision bodies are local siblings of their Visual branch.
		var owner := collider.get_parent()
		if owner != null:
			var visual := owner.get_node_or_null("Visual")
			if visual != null:
				_collect(visual, meshes)
			elif owner is MeshInstance3D:
				_collect(owner, meshes)
	var from := point - direction * .12
	var finish := point + direction * 3.0
	var best := INF
	var result: Dictionary = {}
	for mesh in meshes:
		if not faces.has(mesh.mesh):
			if faces.size() >= 128:
				faces.clear()
			faces[mesh.mesh] = mesh.mesh.get_faces()
		var triangles: PackedVector3Array = faces[mesh.mesh]
		var inverse := mesh.global_transform.affine_inverse()
		var a := inverse * from
		var b := inverse * finish
		if mesh.get_aabb().grow(.001).intersects_segment(a, b) == null:
			continue
		for i in range(0, triangles.size(), 3):
			var hit: Variant = Geometry3D.segment_intersects_triangle(a, b, triangles[i], triangles[i + 1], triangles[i + 2])
			if hit == null:
				continue
			var world_point: Vector3 = mesh.global_transform * (hit as Vector3)
			var distance := world_point.distance_squared_to(from)
			if distance >= best:
				continue
			var local_normal := (triangles[i + 1] - triangles[i]).cross(triangles[i + 2] - triangles[i]).normalized()
			var normal := (mesh.global_basis.inverse().transposed() * local_normal).normalized()
			if normal.dot(direction) > 0.0:
				normal = -normal
			best = distance
			result = {"position": world_point, "normal": normal, "anchor": mesh}
	return result


func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		if mesh.mesh != null and not mesh.mesh is QuadMesh and not mesh.has_meta("surface_mark") and mesh.is_visible_in_tree() and absf(mesh.global_basis.determinant()) > .00000001:
			out.append(mesh)
	for child in node.get_children():
		_collect(child, out)
