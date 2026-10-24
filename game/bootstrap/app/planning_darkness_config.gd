extends RefCounted
## Authored darkness settings shared by planner edits, Undo and scene baking.

static func capture(node: Node) -> Dictionary:
	if not node.has_method("configure_zone") or node.get("room_id") == null:
		return {}
	return {"size": node.get("size"), "darkness": node.get("darkness"),
		"permanent": node.get("permanent"), "room_id": node.get("room_id")}


static func apply(node: Node, data: Dictionary) -> void:
	if data.is_empty() or not node.has_method("configure_zone"):
		return
	node.set("room_id", int(data.room_id))
	node.call("configure_zone", data.size, data.darkness, data.permanent)
