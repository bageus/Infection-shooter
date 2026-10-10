extends RefCounted
## Upload loaded mission materials while the opaque loading overlay remains up.
const BATCH_SIZE := 32
var material_count := 0
var batch_count := 0


func prepare(mission: Node3D, camera: Camera3D, tree: SceneTree, progress: Callable) -> void:
	var materials: Array[Material] = []
	var seen: Dictionary = {}
	var pending: Array[Node] = [mission]
	var started := Time.get_ticks_msec()
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mesh := node as MeshInstance3D
			for surface in mesh.mesh.get_surface_count():
				_append(mesh.get_active_material(surface), materials, seen)
		elif node is MultiMeshInstance3D:
			var multi := node as MultiMeshInstance3D
			_append(multi.material_override, materials, seen)
			if multi.multimesh != null and multi.multimesh.mesh != null:
				for surface in multi.multimesh.mesh.get_surface_count():
					_append(multi.multimesh.mesh.surface_get_material(surface), materials, seen)
		pending.append_array(node.get_children())
		if Time.get_ticks_msec() - started >= 4:
			await tree.process_frame
			started = Time.get_ticks_msec()
	material_count = materials.size()
	var holder := Node3D.new()
	holder.name = "MissionMaterialWarmup"
	camera.add_child(holder)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * .004
	for first in range(0, materials.size(), BATCH_SIZE):
		for i in range(first, mini(first + BATCH_SIZE, materials.size())):
			var sample := MeshInstance3D.new()
			sample.mesh = quad
			sample.material_override = materials[i]
			sample.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(sample)
			# Separate pixels: depth rejection must not prevent texture sampling.
			var slot := i - first
			sample.position = Vector3((slot % 8 - 3.5) * .006, (floori(float(slot) / 8.0) - 1.5) * .006, -.25)
		progress.call(.95 + .04 * float(first + 1) / maxf(materials.size(), 1), "materials")
		await tree.process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
		await tree.process_frame
		batch_count += 1
		for child in holder.get_children():
			child.free()
	holder.free()


func _append(material: Material, materials: Array[Material], seen: Dictionary) -> void:
	if material == null or seen.has(material.get_instance_id()):
		return
	seen[material.get_instance_id()] = true
	materials.append(material)
