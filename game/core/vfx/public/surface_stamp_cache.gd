extends RefCounted
## One caller owns this bounded cache; receiver state and output stay live.
const STAMP := preload("res://game/core/vfx/public/surface_stamp.gd")
const INDEX := preload("res://game/core/vfx/stamp_triangle_index.gd")
const MAX_MESHES := 128
var _entries: Dictionary = {}
var last_triangle_candidates := 0

class Watch extends RefCounted:
	var owner: WeakRef
	var id: int
	func _init(target: RefCounted, key: int) -> void:
		owner = weakref(target)
		id = key
	func changed() -> void:
		var target: RefCounted = owner.get_ref()
		if target != null:
			target.call("_invalidate", id)


func build(receiver: MeshInstance3D, projector: Transform3D, size: Vector2, depth: float, skip_glass: bool = false) -> ArrayMesh:
	last_triangle_candidates = 0
	var transform := receiver.global_transform if receiver.is_inside_tree() else receiver.transform
	if receiver.mesh == null or absf(transform.basis.determinant()) < 1e-10:
		return null
	var to_projector := projector.affine_inverse() * transform
	var volume := AABB(Vector3(-size.x / 2, -size.y / 2, -depth), Vector3(size.x, size.y, depth + .025))
	if not (to_projector * receiver.get_aabb()).intersects(volume):
		return null
	var local_volume := to_projector.affine_inverse() * volume.grow(.00001)
	var prepared: Array = []
	for surface: Dictionary in _surfaces(receiver.mesh):
		var candidates: PackedInt32Array = surface["index"].candidates(local_volume)
		last_triangle_candidates += candidates.size()
		prepared.append({"arrays": surface["arrays"], "candidates": candidates})
	return STAMP._build(receiver, projector, size, depth, skip_glass, prepared)


func _surfaces(mesh: Mesh) -> Array:
	if _entries.has(mesh) and _entries[mesh]["dirty"]:
		_remove(mesh)
	if not _entries.has(mesh):
		while _entries.size() >= MAX_MESHES:
			_remove(_entries.keys()[0])
		var surfaces: Array = []
		for i in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(i)
			surfaces.append({"arrays": arrays, "index": INDEX.new(arrays)})
		var watch := Watch.new(self, mesh.get_instance_id())
		var callback: Callable = watch.changed
		_entries[mesh] = {"surfaces": surfaces, "watch": watch, "callback": callback, "dirty": false}
		mesh.changed.connect(callback)
	return _entries[mesh]["surfaces"]


func _invalidate(id: int) -> void:
	for mesh: Mesh in _entries:
		if mesh.get_instance_id() == id:
			_entries[mesh]["dirty"] = true
			return


func _remove(mesh: Mesh) -> void:
	var callback: Callable = _entries[mesh]["callback"]
	if mesh.changed.is_connected(callback):
		mesh.changed.disconnect(callback)
	_entries.erase(mesh)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for mesh: Mesh in _entries:
			var callback: Callable = _entries[mesh]["callback"]
			if mesh.changed.is_connected(callback):
				mesh.changed.disconnect(callback)
		_entries.clear()
