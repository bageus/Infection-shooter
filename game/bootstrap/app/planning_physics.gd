extends RefCounted
## Resume free bodies only after the authored map snapshot; anchors stay fixed.
static func resume(nodes: Array) -> void:
	for node: Node in nodes:
		if not is_instance_valid(node):
			continue
		if node.has_method("set_runtime_physics"):
			node.call("set_runtime_physics", true)
		if node is RigidBody3D and not node.freeze:
			node.sleeping = node.has_meta("planning_settled_transform") and node.get_meta("planning_settled_transform") == node.transform
		resume(node.get_children())


## Save regenerates automatic wall fixtures even when their authored placement is
## unchanged. Carry preparation across an identical anchored replacement.
static func capture_anchors(nodes: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node: Node in nodes:
		if not is_instance_valid(node) or not node is RigidBody3D or not node.freeze:
			continue
		if node.has_meta("planning_auto_fixture") and node.has_meta("planning_settled_transform") and node.get_meta("planning_settled_transform") == node.transform:
			result.append({"scene": str(node.get_meta("planning_scene_path", "")), "transform": node.transform, "count": node.get_meta("planning_settled_count", -1)})
	return result


static func restore_anchors(nodes: Array, stamps: Array[Dictionary]) -> void:
	for node: Node in nodes:
		if not is_instance_valid(node) or not node is RigidBody3D or not node.freeze or not node.has_meta("planning_auto_fixture"):
			continue
		for stamp in stamps:
			if str(node.get_meta("planning_scene_path", "")) == stamp.scene and (stamp.transform as Transform3D).is_equal_approx(node.transform):
				node.set_meta("planning_settled_transform", node.transform)
				node.set_meta("planning_settled_count", stamp.count)
				break
