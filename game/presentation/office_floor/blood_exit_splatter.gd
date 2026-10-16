extends RefCounted
## Bounded directional surface stamps from an already confirmed body exit.
static func emit(renderer: Node3D, surfaces: Node3D, point: Vector3, direction: Vector3, energy: float, excluded: Array[RID]) -> void:
	if direction.length_squared() < 0.0001:
		return
	var axis := direction.normalized()
	var strength := clampf(energy / 110.0, 0.0, 1.0)
	var sizes: Vector2 = renderer.get("splatter_size") * lerpf(0.7, 1.6, strength)
	var reach := lerpf(1.2, 3.0, strength)
	var found := false
	for angle in [0.0, -0.22, 0.22]:
		var flight := axis.rotated(Vector3.UP, angle)
		var surface: Dictionary = surfaces.call("find_behind", point, flight, excluded, reach)
		if not surface.is_empty():
			found = true
			renderer.call("_submit", "splatter", surface, flight, sizes, true, strength > 0.5)
	if not found:
		var landing := point + axis * lerpf(0.4, 1.0, strength)
		var floor_hit: Dictionary = surfaces.call("find_floor", landing, excluded)
		renderer.call("_submit", "splatter", floor_hit, axis, sizes, true, strength > 0.5)
