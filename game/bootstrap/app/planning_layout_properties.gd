extends RefCounted
## Restore optional authored properties before a map object enters the tree.

const DOOR_OPTIONS := preload("res://game/bootstrap/app/planning_door_options.gd")

static func restore(node: Node3D, record: Dictionary) -> void:
	if node.has_method("configure_blood") and record.has("blood_texture"):
		node.call("configure_blood", str(record["blood_texture"]), str(record.get("blood_surface", "floor")))
	if node.has_method("configure_decor_pose") and record.get("decor_pose") is Dictionary:
		node.call("configure_decor_pose", record["decor_pose"])
	if node.has_method("configure_display") and record.get("display") is Dictionary:
		node.call("configure_display", record["display"])
	if node.has_method("configure_loot") and record.get("loot") is Dictionary:
		node.call("configure_loot", record["loot"])
	var door := DOOR_OPTIONS.lockable_controller(node)
	if door != null and DOOR_OPTIONS.is_valid_state(record.get("door_lock", "")):
		door.call("configure_lock_state", StringName(str(record["door_lock"])))
	if node.has_method("configure_stats") and record.get("enemy_stats") is Dictionary:
		node.call("configure_stats", record["enemy_stats"])
	if node.has_method("configure_blood_normal"):
		var default_normal: Vector3 = node.get("surface_normal")
		var blood_normal: Array = record.get("blood_normal", [default_normal.x, default_normal.y, default_normal.z])
		node.call("configure_blood_normal", Vector3(float(blood_normal[0]), float(blood_normal[1]), float(blood_normal[2])))
		node.call("configure_blood_attachment", record.get("blood_attachment", {}))
	if record.has("object_id"):
		node.set_meta("planning_object_id", str(record["object_id"]))
