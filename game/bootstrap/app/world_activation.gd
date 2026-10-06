extends Node
## Restore authored roots when leaving planning; distance never disables geometry.
var roots: Array = []


func setup(managed_roots: Array) -> void:
	roots = managed_roots
	rebuild()


func rebuild() -> void:
	for branch: Node in roots:
		if not is_instance_valid(branch):
			continue
		for child in branch.get_children():
			if child is Node3D:
				(child as Node3D).visible = true
				if child.process_mode == Node.PROCESS_MODE_DISABLED:
					child.process_mode = Node.PROCESS_MODE_INHERIT
				_restore_streamed_collision(child)


func _restore_streamed_collision(node: Node) -> void:
	# Never reactivate a pane that was disabled by real destruction.
	if node is CollisionShape3D and node.has_meta("chunk_streamed_disabled"):
		node.remove_meta("chunk_streamed_disabled")
		(node as CollisionShape3D).set_deferred("disabled", false)
	for child in node.get_children():
		_restore_streamed_collision(child)
