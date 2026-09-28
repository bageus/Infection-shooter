extends RefCounted

# Damage marks follow their pane and share the existing 40-mark impact budget.
static var _textures: Array[String] = []
static var _scanned := false


static func spawn(pane: StaticBody3D, point: Vector3, normal: Vector3) -> void:
	var mark := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = 2
	var pool := pane.get_tree().current_scene.get_node_or_null("ImpactEffects")
	var assets := _available_textures()
	if not assets.is_empty():
		var path: String = assets.pick_random()
		if pool != null:
			material.albedo_texture = pool.call("texture_for", path) as Texture2D
		if material.albedo_texture == null:
			material.albedo_texture = load(path) as Texture2D
	if material.albedo_texture != null:
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * randf_range(0.38, 0.65)
		quad.material = material
		mark.mesh = quad
	else:
		mark.mesh = _fallback_fracture(material)
	pane.add_child(mark)
	var outward := normal.normalized() if not normal.is_zero_approx() else Vector3.FORWARD
	mark.global_position = point + outward * 0.025
	var up := Vector3.FORWARD if absf(outward.y) > 0.9 else Vector3.UP
	mark.global_basis = Basis.looking_at(-outward, up) * Basis(Vector3.FORWARD, randf() * TAU)
	if pool != null:
		pool.call("register_mark", mark)


static func _available_textures() -> Array[String]:
	if _scanned:
		return _textures
	_scanned = true
	for folder in ["res://models/objects/textures/", "res://models/objects/enviroments/01/"]:
		var directory := DirAccess.open(folder)
		if directory == null:
			continue
		for file in directory.get_files():
			var name := file.to_lower()
			if ("crack" in name or "glass_fracture" in name) and "wood" not in name and (name.ends_with(".png") or name.ends_with(".webp")):
				_textures.append(folder + file)
	return _textures


static func _fallback_fracture(material: Material) -> Mesh:
	material.albedo_color = Color(0.82, 0.94, 1.0, 0.72)
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var arms := randi_range(6, 11)
	for i in arms:
		var angle := TAU * float(i) / float(arms) + randf_range(-0.16, 0.16)
		var length := randf_range(0.13, 0.29)
		var bend := Vector3(cos(angle) * length * 0.48, sin(angle) * length * 0.48, 0)
		var end := Vector3(cos(angle + 0.18) * length, sin(angle + 0.18) * length, 0)
		lines.surface_add_vertex(Vector3.ZERO)
		lines.surface_add_vertex(bend)
		lines.surface_add_vertex(bend)
		lines.surface_add_vertex(end)
	lines.surface_end()
	return lines
