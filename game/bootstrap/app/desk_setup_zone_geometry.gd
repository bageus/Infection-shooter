extends RefCounted

# Zones contain the placement point. Visible geometry may extend past the
# boundary: the same zone can accommodate small position and angle variations.
static func fits_zone(desk: Node3D, zone: Dictionary, item: Node3D) -> bool:
	var point := desk.to_local(item.global_position)
	var offset := Vector3(point.x - float(zone["x"]), 0, point.z - float(zone["z"])).rotated(Vector3.UP, -deg_to_rad(float(zone.get("angle", 0.0))))
	if absf(offset.x) > float(zone["width"]) * 0.5 + 0.002 or absf(offset.z) > float(zone["depth"]) * 0.5 + 0.002:
		return false
	var mesh_found := false
	var lowest := INF
	var pending: Array[Node] = [item]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		if current is MeshInstance3D:
			var mesh := current as MeshInstance3D
			if mesh.mesh != null and mesh.is_visible_in_tree() and absf(mesh.global_basis.determinant()) > 0.000001:
				mesh_found = true
				var box := mesh.get_aabb()
				for x in [box.position.x, box.end.x]:
					for z in [box.position.z, box.end.z]:
						for y in [box.position.y, box.end.y]:
							var world := mesh.to_global(Vector3(x, y, z))
							lowest = minf(lowest, world.y)
		for child in current.get_children():
			pending.append(child)
	var surface_y := desk.to_global(Vector3.UP * float(zone.get("height", 0.0))).y
	return mesh_found and absf(lowest - surface_y) < 0.28


static func matching_zone(desk: Node3D, zones: Array, item: Node3D, hint: int = -1) -> int:
	if hint >= 0:
		return hint if hint < zones.size() and zones[hint] is Dictionary and fits_zone(desk, zones[hint], item) else -1
	for index in zones.size():
		if zones[index] is Dictionary and fits_zone(desk, zones[index], item):
			return index
	return -1
