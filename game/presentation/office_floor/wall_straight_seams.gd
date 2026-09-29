extends Node3D

# Visual-only end caps hide sub-centimeter cracks between aligned wall modules.
const HALF_LENGTH := 1.0
const JOIN_DISTANCE := 0.16

var _covers: Array[MeshInstance3D] = []
var _neighbors: Array[Node3D] = []
var _refresh_queued := false


func _ready() -> void:
	add_to_group("straight_wall_join")
	set_notify_transform(true)
	var parent := get_parent()
	if parent != null:
		parent.child_entered_tree.connect(_on_sibling_changed)
		parent.child_exiting_tree.connect(_on_sibling_changed)
	_queue_refresh()


func _exit_tree() -> void:
	var parent := get_parent()
	if parent != null:
		parent.child_entered_tree.disconnect(_on_sibling_changed)
		parent.child_exiting_tree.disconnect(_on_sibling_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_inside_tree():
		_queue_refresh()
		for neighbor in _neighbors:
			if is_instance_valid(neighbor):
				neighbor.call("_queue_refresh")


func _on_sibling_changed(sibling: Node) -> void:
	if sibling.is_in_group("straight_wall_join"):
		_queue_refresh()


func _queue_refresh() -> void:
	if not is_inside_tree() or _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_refresh_seams")


func _refresh_seams() -> void:
	_refresh_queued = false
	for cover in _covers:
		if is_instance_valid(cover):
			cover.queue_free()
	_covers.clear()
	_neighbors.clear()
	if get_parent() == null:
		return
	for side in [-1.0, 1.0]:
		var end := to_global(Vector3(side * HALF_LENGTH, 1.3, 0))
		for sibling in get_parent().get_children():
			if sibling == self or not sibling is Node3D or not sibling.is_in_group("straight_wall_join"):
				continue
			var other := sibling as Node3D
			if absf(global_basis.x.normalized().dot(other.global_basis.x.normalized())) < 0.995:
				continue
			for other_side in [-1.0, 1.0]:
				var other_end := other.to_global(Vector3(other_side * HALF_LENGTH, 1.3, 0))
				if end.distance_to(other_end) > JOIN_DISTANCE:
					continue
				if not _neighbors.has(other):
					_neighbors.append(other)
					_add_cover(side)
				break
			if _covers.size() > 0 and _covers[_covers.size() - 1].get_meta("side") == side:
				break


func _add_cover(side: float) -> void:
	var cover := MeshInstance3D.new()
	cover.name = "WallJointCover"
	cover.set_meta("side", side)
	var box := BoxMesh.new()
	box.size = Vector3(0.20, 2.64, 0.26)
	var visual := get_node_or_null("Visual")
	var meshes := visual.find_children("*", "MeshInstance3D", true, false) if visual != null else []
	var source := meshes[0] as MeshInstance3D if not meshes.is_empty() else null
	if source != null:
		box.material = source.get_active_material(0)
	cover.mesh = box
	add_child(cover, false, Node.INTERNAL_MODE_FRONT)
	cover.position = Vector3(side * HALF_LENGTH, 1.3, 0)
	_covers.append(cover)
