extends RefCounted
## Resume free bodies only after the authored map snapshot; anchors stay fixed.
static func resume(nodes: Array) -> void:
	for candidate: Variant in nodes:
		if not is_instance_valid(candidate) or not candidate is Node:
			continue
		var node: Node = candidate
		if node.has_method("set_runtime_physics"):
			node.call("set_runtime_physics", true)
		if not is_instance_valid(node):
			continue
		resume(node.get_children())
		if node is RigidBody3D and not node.freeze:
			var prepared: bool = node.has_meta("planning_settled_transform") and node.get_meta("planning_settled_transform") == node.transform
			node.sleeping = prepared
			PhysicsServer3D.body_set_state(node.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, prepared)


## Save regenerates automatic wall fixtures even when their authored placement is
## unchanged. Carry preparation across an identical anchored replacement.
static func capture_anchors(nodes: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for candidate: Variant in nodes:
		if not is_instance_valid(candidate) or not candidate is Node:
			continue
		var node: Node = candidate
		if not is_instance_valid(node) or not node is RigidBody3D or not node.freeze:
			continue
		if node.has_meta("planning_auto_fixture") and node.has_meta("planning_settled_transform") and node.get_meta("planning_settled_transform") == node.transform:
			result.append({"scene": str(node.get_meta("planning_scene_path", "")), "transform": node.transform, "count": node.get_meta("planning_settled_count", -1)})
	return result


static func restore_anchors(nodes: Array, stamps: Array[Dictionary]) -> void:
	for candidate: Variant in nodes:
		if not is_instance_valid(candidate) or not candidate is Node:
			continue
		var node: Node = candidate
		if not is_instance_valid(node) or not node is RigidBody3D or not node.freeze or not node.has_meta("planning_auto_fixture"):
			continue
		for stamp in stamps:
			if str(node.get_meta("planning_scene_path", "")) == stamp.scene and (stamp.transform as Transform3D).is_equal_approx(node.transform):
				node.set_meta("planning_settled_transform", node.transform)
				node.set_meta("planning_settled_count", stamp.count)
				break
