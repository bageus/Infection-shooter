extends RefCounted
## Cache tree composition, never visibility, resource assignments or transforms.
const MAX_ROOTS := 128
const WATCH := preload("res://game/features/combat/impact_cache_watch.gd")
var _entries: Dictionary = {}
var rebuilds := 0


func gather(root: Node) -> Array[MeshInstance3D]:
	var id := root.get_instance_id()
	if not _entries.has(id) or _entries[id]["dirty"]:
		_remove(id)
		while _entries.size() >= MAX_ROOTS:
			_remove(_entries.keys()[0])
		var watch := WATCH.new(self, &"_invalidate", id)
		var callback: Callable = watch.changed
		var entry := {"dirty": false, "meshes": [], "nodes": [], "callback": callback, "watch": watch}
		_collect(root, entry)
		_entries[id] = entry
		rebuilds += 1
	var result: Array[MeshInstance3D] = []
	for reference: WeakRef in _entries[id]["meshes"]:
		var mesh := reference.get_ref() as MeshInstance3D
		if mesh != null and _eligible(mesh, root):
			result.append(mesh)
	return result


func _collect(node: Node, entry: Dictionary) -> void:
	entry["nodes"].append(weakref(node))
	node.child_order_changed.connect(entry["callback"])
	if node is MeshInstance3D:
		entry["meshes"].append(weakref(node))
	for child in node.get_children():
		_collect(child, entry)


func _eligible(mesh: MeshInstance3D, root: Node) -> bool:
	if mesh.mesh == null or mesh.mesh is QuadMesh or mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY or not mesh.is_visible_in_tree() or absf(mesh.global_basis.determinant()) <= .00000001:
		return false
	var node: Node = mesh
	while node != null:
		if node.has_meta("surface_mark") or node.has_meta("blood_effect"):
			return false
		if node == root:
			return true
		node = node.get_parent()
	return false


func _invalidate(id: int) -> void:
	if _entries.has(id):
		_entries[id]["dirty"] = true


func _remove(id: int) -> void:
	if not _entries.has(id):
		return
	var entry: Dictionary = _entries[id]
	for reference: WeakRef in entry["nodes"]:
		var node := reference.get_ref() as Node
		if node != null and node.child_order_changed.is_connected(entry["callback"]):
			node.child_order_changed.disconnect(entry["callback"])
	_entries.erase(id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# RefCounted is already at zero: clean entries without instance helpers.
		for entry: Dictionary in _entries.values():
			for reference: WeakRef in entry["nodes"]:
				var node := reference.get_ref() as Node
				if node != null and node.child_order_changed.is_connected(entry["callback"]):
					node.child_order_changed.disconnect(entry["callback"])
		_entries.clear()
