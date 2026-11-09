extends RefCounted
## Merges the meshes of fixed structure (walls, columns, floor pads, lift cabins) into a few big meshes,
## one per map chunk and material, so the renderer issues one draw call where it issued dozens.
## Colliders stay on the original nodes; only their MeshInstance3D nodes are hidden. Doors, glass and
## anything destructible are not in SCENES and keep drawing on their own.
const SCENES := ["wall_straight.tscn", "column.tscn", "floor_pad.tscn", "wall_half_panel.tscn", "elevator_cabin_freight.tscn", "elevator_cabin_passenger.tscn"]
const CHUNK := 12.0
const GROUP := &"static_merged"
const SOURCES := &"static_merge_sources"


## Builds the merged meshes for the placed nodes and hides the originals; returns how many sources were merged.
static func merge(placed: Array, parent: Node3D) -> int:
	var batches := {}
	var sources: Array[MeshInstance3D] = []
	for node in placed:
		if not is_instance_valid(node) or not (node is Node3D) or String(node.get_meta("planning_scene_path", "")).get_file() not in SCENES:
			continue
		for found in (node as Node3D).find_children("*", "MeshInstance3D", true, false):
			var mesh_node := found as MeshInstance3D
			if mesh_node.mesh == null or mesh_node.skeleton != NodePath() or mesh_node.material_override != null or mesh_node.has_meta("planning_bounds_excluded") or not _shown_in(mesh_node, node):
				continue
			if absf(mesh_node.global_basis.determinant()) < 0.000001:
				continue
			if not _all_opaque(mesh_node):
				continue
			sources.append(mesh_node)
			var cell := Vector2i(floori(mesh_node.global_position.x / CHUNK), floori(mesh_node.global_position.z / CHUNK))
			for surface in mesh_node.mesh.get_surface_count():
				var material := mesh_node.get_active_material(surface)
				var key := [cell, material.get_instance_id(), mesh_node.cast_shadow, mesh_node.layers]
				if not batches.has(key):
					batches[key] = {"material": material, "shadow": mesh_node.cast_shadow, "layers": mesh_node.layers, "items": []}
				batches[key].items.append([mesh_node, surface])
	if sources.is_empty():
		return 0
	var holder := Node3D.new()
	holder.name = "StaticMerged"
	holder.add_to_group(GROUP)
	holder.set_meta(SOURCES, sources)
	parent.add_child(holder)
	for key in batches:
		var built := _build(batches[key].items)
		if built == null:
			continue
		var instance := MeshInstance3D.new()
		instance.mesh = built
		instance.set_surface_override_material(0, batches[key].material)
		instance.cast_shadow = batches[key].shadow
		instance.layers = batches[key].layers
		holder.add_child(instance)
	for source in sources:
		source.visible = false
	return sources.size()


## Brings the original meshes back and removes the merged ones (the planner edits single walls).
static func restore(tree: SceneTree) -> void:
	for holder in tree.get_nodes_in_group(GROUP):
		for source in holder.get_meta(SOURCES, []):
			if is_instance_valid(source):
				source.visible = true
		holder.queue_free()
		holder.remove_from_group(GROUP)


## Only plain opaque materials are merged: shaders, blending and script-driven overlays (wall base shadow strips) stay as they are.
static func _all_opaque(mesh_node: MeshInstance3D) -> bool:
	for surface in mesh_node.mesh.get_surface_count():
		var material := mesh_node.get_active_material(surface) as BaseMaterial3D
		if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return false
	return true


## True when the mesh and every parent up to the placed node are visible (the whole level may still be hidden while loading).
static func _shown_in(mesh_node: Node3D, root: Node3D) -> bool:
	var current: Node = mesh_node
	while current != null and current != root.get_parent():
		if current is Node3D and not (current as Node3D).visible:
			return false
		current = current.get_parent()
	return true


static func _build(items: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var tangents := PackedFloat32Array()
	for item in items:
		var mesh_node: MeshInstance3D = item[0]
		var arrays := mesh_node.mesh.surface_get_arrays(item[1])
		var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if source_vertices.is_empty():
			continue
		var transform := mesh_node.global_transform
		var normal_basis := transform.basis.inverse().transposed()
		var offset := vertices.size()
		for vertex in source_vertices:
			vertices.append(transform * vertex)
		var source_normals: Variant = arrays[Mesh.ARRAY_NORMAL]
		for index in source_vertices.size():
			normals.append((normal_basis * source_normals[index]).normalized() if source_normals != null else Vector3.UP)
		var source_uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
		for index in source_vertices.size():
			uvs.append(source_uvs[index] if source_uvs != null else Vector2.ZERO)
		var source_tangents: Variant = arrays[Mesh.ARRAY_TANGENT]
		for index in source_vertices.size():
			var tangent := Vector3(source_tangents[index * 4], source_tangents[index * 4 + 1], source_tangents[index * 4 + 2]) if source_tangents != null else Vector3.RIGHT
			tangent = (transform.basis * tangent).normalized()
			tangents.append_array([tangent.x, tangent.y, tangent.z, source_tangents[index * 4 + 3] if source_tangents != null else 1.0])
		var source_indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if source_indices == null:
			for index in source_vertices.size():
				indices.append(offset + index)
		else:
			for index: int in source_indices:
				indices.append(offset + index)
	if vertices.is_empty():
		return null
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = vertices
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_TEX_UV] = uvs
	out[Mesh.ARRAY_TANGENT] = tangents
	out[Mesh.ARRAY_INDEX] = indices
	var merged := ArrayMesh.new()
	merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return merged
