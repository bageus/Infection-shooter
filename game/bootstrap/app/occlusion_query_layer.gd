extends RefCounted
## Bootstrap-owned, temporary query bit on injected structural colliders only.
const MASK := 1 << 8
var records: Dictionary = {}


func add_root(node: Node3D) -> void:
	if node is CollisionObject3D and not node is Area3D:
		var id := node.get_instance_id()
		if not records.has(id):
			var callback := _visibility_changed.bind(weakref(node))
			records[id] = {"body": weakref(node), "callback": callback}
			node.visibility_changed.connect(callback)
		_sync(node)
	for child in node.get_children():
		if child is Node3D:
			add_root(child)


func _visibility_changed(weak_body: WeakRef) -> void:
	var body := weak_body.get_ref() as CollisionObject3D
	if body != null:
		_sync(body)


func _sync(body: CollisionObject3D) -> void:
	# Never resurrect a collider disabled by destruction or the planner.
	if body.is_visible_in_tree() and body.collision_layer & 3:
		body.collision_layer |= MASK
	else:
		body.collision_layer &= ~MASK


func remove_root(node: Node) -> void:
	var id := node.get_instance_id()
	if records.has(id):
		_restore(records[id])
		records.erase(id)
	for child in node.get_children():
		remove_root(child)


func _restore(record: Dictionary) -> void:
	var body := record.body.get_ref() as CollisionObject3D
	if body != null:
		body.collision_layer &= ~MASK
		if body.visibility_changed.is_connected(record.callback):
			body.visibility_changed.disconnect(record.callback)


func clear() -> void:
	for record: Dictionary in records.values():
		_restore(record)
	records.clear()
