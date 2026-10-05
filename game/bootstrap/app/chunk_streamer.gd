extends Node
## Legacy planner lifecycle adapter. Distance-based world streaming is retired.
## Geometry, collisions and silhouettes remain present at every player position.
var player: Node3D
var roots: Array = []
var enabled := false


func setup(target: Node3D, managed_roots: Array) -> void:
	player = target
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


func set_runtime_enabled(_value: bool) -> void:
	enabled = false
	rebuild()


func _restore_streamed_collision(node: Node) -> void:
	# Never reactivate a pane that was disabled by real destruction.
	if node is CollisionShape3D and node.has_meta("chunk_streamed_disabled"):
		node.remove_meta("chunk_streamed_disabled")
		(node as CollisionShape3D).set_deferred("disabled", false)
	for child in node.get_children():
		_restore_streamed_collision(child)
