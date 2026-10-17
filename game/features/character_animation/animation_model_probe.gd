extends RefCounted
## Read-only geometry and playback discovery.

static func feet_height(node: Node) -> float:
	var lowest := INF
	var meshes: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for mesh_node in meshes:
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance.mesh != null:
			var offset := 0.0 if mesh_instance == node else mesh_instance.position.y
			lowest = minf(lowest, mesh_instance.get_aabb().position.y + offset)
	return 0.0 if lowest == INF else lowest


static func find_animation_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := find_animation_player(child)
		if found != null:
			return found
	return null
