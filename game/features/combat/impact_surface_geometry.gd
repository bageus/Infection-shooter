extends RefCounted
## Project a broad-phase collider hit onto the visible mesh, not its bounding box.
const TRIANGLE_INDEX := preload("res://game/features/combat/impact_triangle_index.gd")
const RECEIVER_CACHE := preload("res://game/features/combat/impact_receiver_cache.gd")
const MAX_INDEXED_MESHES := 128
var _indices: Dictionary = {}
var _receivers := RECEIVER_CACHE.new()
var last_triangle_tests := 0
var visuals: Dictionary = {}


func register(collider: Node3D, visual: Node3D) -> void:
	visuals[collider.get_instance_id()] = weakref(visual)



func resolve(collider: Node3D, point: Vector3, direction: Vector3) -> Dictionary:
	last_triangle_tests = 0
	if not is_instance_valid(collider):
		return {}
	var meshes := receivers(collider)
	var from := point - direction * .12
	var finish := point + direction * 3.0
	var best := INF
	var result: Dictionary = {}
	for mesh in meshes:
		var inverse := mesh.global_transform.affine_inverse()
		var a := inverse * from
		var b := inverse * finish
		if mesh.get_aabb().grow(.001).intersects_segment(a, b) == null:
			continue
		var index: RefCounted = _index_for(mesh.mesh)
		var triangles: PackedVector3Array = index.get("triangles")
		for i in index.call("candidates", a, b):
			last_triangle_tests += 1
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


func receivers(collider: Node3D) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if visuals.has(collider.get_instance_id()):
		var visual := (visuals[collider.get_instance_id()] as WeakRef).get_ref() as Node
		if visual != null:
			meshes.append_array(_receivers.gather(visual))
	meshes.append_array(_receivers.gather(collider))
	if meshes.is_empty():
		# Structural collision bodies are local siblings of their Visual branch.
		var owner := collider.get_parent()
		if owner != null:
			var visual := owner.get_node_or_null("Visual")
			if visual != null:
				meshes.append_array(_receivers.gather(visual))
			elif owner is MeshInstance3D:
				meshes.append_array(_receivers.gather(owner))
	return meshes



func _index_for(mesh: Mesh) -> RefCounted:
	if not _indices.has(mesh):
		while _indices.size() >= MAX_INDEXED_MESHES:
			_remove_index(_indices.keys()[0])
		var id := mesh.get_instance_id()
		var callback := _changed.bind(weakref(self), id)
		_indices[mesh] = {"index": TRIANGLE_INDEX.new(mesh.get_faces()), "callback": callback}
		mesh.changed.connect(callback)
	return _indices[mesh]["index"]


func _invalidate_index(id: int) -> void:
	for mesh: Mesh in _indices.keys():
		if mesh.get_instance_id() == id:
			_remove_index(mesh)
			return


func _remove_index(mesh: Mesh) -> void:
	var callback: Callable = _indices[mesh]["callback"]
	if mesh.changed.is_connected(callback):
		mesh.changed.disconnect(callback)
	_indices.erase(mesh)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for mesh: Mesh in _indices.keys():
			_remove_index(mesh)


static func _changed(reference: WeakRef, id: int) -> void:
	var geometry: RefCounted = reference.get_ref()
	if geometry != null:
		geometry.call("_invalidate_index", id)
