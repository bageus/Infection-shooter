extends RefCounted
## Planner surface probes and stable authored attachment restoration.


static func probe(session: Variant, placing: Node3D, screen: Vector2) -> Vector3:
	var mode := str(placing.call("get_blood_config")["surface"])
	var camera: Camera3D = session.camera
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 300.0, 7)
	var excluded: Array[RID] = []
	var pool: Node = session.host.get("impact_pool")
	for _attempt in range(16):
		query.exclude = excluded
		var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			break
		var normal: Vector3 = hit["normal"]
		var point: Vector3 = hit["position"]
		var eligible := mode == "object" or (mode == "floor" and normal.y > .75 and _floor_surface(hit["collider"])) or (mode == "wall" and absf(normal.y) < .35 and _wall_surface(hit["collider"]))
		if eligible:
			var anchor: Node3D
			if pool != null and mode != "floor":
				var surface: Dictionary = pool.call("resolve_surface", hit["collider"], point, direction)
				if not surface.is_empty():
					point = surface["position"]
					normal = surface["normal"]
					anchor = surface["anchor"]
			if mode == "floor":
				point.y = maxf(point.y, _floor_height(session))
			placing.call("configure_blood_normal", placing.global_basis.inverse() * normal)
			placing.set_meta("blood_probe_anchor", weakref(anchor) if anchor != null else null)
			return point
		excluded.append(hit["rid"])
	if mode != "floor" or absf(direction.y) < .00001:
		return Vector3.INF
	var distance := (_floor_height(session) - origin.y) / direction.y
	if distance < 0:
		return Vector3.INF
	placing.call("configure_blood_normal", Vector3.UP)
	placing.set_meta("blood_probe_anchor", null)
	return origin + direction * distance


static func _floor_height(session: Variant) -> float:
	var floor: Node3D = session.host.get_node_or_null("Floor")
	return floor.global_position.y + float(floor.get("tile_y")) + .0125 if floor != null else .0135


static func apply_probe(placing: Node3D, preview: Node3D) -> void:
	if not placing.has_method("configure_blood_normal") or preview == null:
		return
	var normal: Vector3 = preview.get("surface_normal")
	placing.call("configure_blood_normal", placing.global_basis.inverse() * (preview.global_basis * normal))
	var reference: Variant = preview.get_meta("blood_probe_anchor") if preview.has_meta("blood_probe_anchor") else null
	var anchor: Node3D = reference.get_ref() if reference is WeakRef else null
	if anchor == null:
		return
	var owner: Node = anchor
	while owner != null and not owner.has_meta("planning_scene_path"):
		owner = owner.get_parent()
	if owner == null:
		return
	if str(owner.get_meta("planning_object_id", "")).is_empty():
		owner.set_meta("planning_object_id", "object_%d" % Time.get_ticks_usec())
	placing.call("attach_blood", anchor, str(owner.get_meta("planning_object_id")))


static func restore_attachments(roots: Array) -> void:
	var all: Array[Node] = []
	for branch: Node in roots:
		_collect(branch, all)
	var owners: Dictionary = {}
	for node in all:
		if node.has_meta("planning_object_id"):
			owners[str(node.get_meta("planning_object_id"))] = node
	for node in all:
		if not node.has_method("get_blood_attachment"):
			continue
		var config: Dictionary = node.call("get_blood_attachment")
		if str(config.get("owner", "")).is_empty():
			continue
		var owner: Node = owners.get(str(config.get("owner", "")))
		if owner == null:
			continue
		var anchor := owner.find_child(str(config["mesh"]), true, false) as Node3D
		if anchor != null:
			node.call("attach_blood", anchor, str(config["owner"]))


static func _collect(node: Node, out: Array[Node]) -> void:
	out.append(node)
	for child in node.get_children():
		_collect(child, out)


static func _floor_surface(node: Node) -> bool:
	while node != null:
		if "floor" in node.name.to_lower():
			return true
		if node.has_method("has_display") and "01_floor_" in str(node.get("model_path")):
			return true
		node = node.get_parent()
	return false


static func _wall_surface(node: Node) -> bool:
	while node != null:
		if node.is_in_group("camera_occluder"):
			return true
		node = node.get_parent()
	return false


static func preview_projection(placing: Node3D) -> void:
	if not placing.has_method("configure_projection"):
		return
	var reference: Variant = placing.get_meta("blood_probe_anchor") if placing.has_meta("blood_probe_anchor") else null
	var anchor: Node3D = reference.get_ref() if reference is WeakRef else null
	placing.call("configure_projection", anchor)
