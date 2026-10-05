extends RefCounted
## Resume free bodies only after the authored map snapshot; anchors stay fixed.
static func resume(nodes: Array) -> void:
	for node: Node in nodes:
		if not is_instance_valid(node):
			continue
		if node.has_method("set_runtime_physics"):
			node.call("set_runtime_physics", true)
		if node is RigidBody3D and not node.freeze:
			node.sleeping = false
		resume(node.get_children())
