extends RefCounted

const ATLAS := preload("res://game/core/vfx/public/surface_atlases.gd")


static func spawn(pane: StaticBody3D, point: Vector3, normal: Vector3, max_size: float = 0.65) -> MeshInstance3D:
	var mark := MeshInstance3D.new()
	mark.set_meta("surface_mark", true)
	var variant := randi_range(0, 7)
	var material := ATLAS.material(ATLAS.GLASS, variant)
	material.render_priority = 2
	var pool := pane.get("impact_pool") as Node
	if pool != null and pool.has_method("resolve_surface"):
		var surface: Dictionary = pool.call("resolve_surface", pane, point, -normal)
		if not surface.is_empty():
			point = surface["position"]
			normal = surface["normal"]
	var quad := QuadMesh.new()
	var size := minf(randf_range(0.38, 0.65), max_size)
	quad.size = Vector2.ONE * size
	var center: Vector2 = ATLAS.GLASS_CENTERS[variant]
	quad.center_offset = Vector3((0.5 - center.x) * size, (center.y - 0.5) * size, 0.0)
	quad.material = material
	mark.mesh = quad
	pane.add_child(mark)
	var outward := normal.normalized() if not normal.is_zero_approx() else Vector3.FORWARD
	mark.global_position = point + outward * 0.0015
	var up := Vector3.FORWARD if absf(outward.y) > 0.9 else Vector3.UP
	mark.global_basis = Basis.looking_at(-outward, up) * Basis(Vector3.FORWARD, randf() * TAU)
	if pool != null:
		pool.call("register_mark", mark)
	return mark


