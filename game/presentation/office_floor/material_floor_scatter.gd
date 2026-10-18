extends RefCounted
const PATTERN := preload("res://game/presentation/office_floor/glass_floor_scatter.gd")
const ATLASES := preload("res://game/presentation/office_floor/debris_atlases.gd")
const SMALL_KINDS := ["wood", "paper", "plastic"]
const SMALL_SCALE := 0.5 # Wood, paper and plastic read as chips, not sheets.
const CHIP_SCALE := 0.6 # Each main piece gets one smaller companion chip.
const CHIP_SPREAD := 0.22


static func scatter(floor_view: Node3D, center: Vector3, footprint: Vector2, recipe: Array[String], direction: Vector3, excluded: Array[RID]) -> void:
	if not center.is_finite() or not footprint.is_finite() or recipe.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	var width := clampf(maxf(footprint.x, footprint.y), 0.3, 5.0)
	var angle := (0.0 if footprint.x >= footprint.y else PI * 0.5) + rng.randf_range(-0.45, 0.45)
	var axis := Vector2(cos(angle), sin(angle))
	var across := Vector2(-axis.y, axis.x)
	var pattern := PATTERN.build_pattern(width, rng)
	var materials := recipe.duplicate()
	while materials.size() > pattern.size():
		materials.remove_at(0) # Keep the rare additions when the total footprint is smaller.
	for index in range(materials.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var value: String = materials[index]
		materials[index] = materials[other]
		materials[other] = value
	var push := floor_view.global_basis.inverse() * direction
	for index in materials.size():
		var mark: Dictionary = pattern[floori(index * float(pattern.size() - 1) / maxi(materials.size() - 1, 1))]
		var offset: Vector2 = mark.offset
		var planar := Vector2(center.x, center.z) + axis * offset.x + across * offset.y
		planar += Vector2(push.x, push.z).limit_length(1.0) * 0.12
		var start := floor_view.to_global(Vector3(center.x, 0.22, center.z))
		var end := floor_view.to_global(Vector3(planar.x, 0.22, planar.y))
		var ray := PhysicsRayQueryParameters3D.create(start, end, 1)
		ray.exclude = excluded
		if not floor_view.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		var kind: String = materials[index]
		var frame := ATLASES.choose_frame(kind, absf(offset.y) > 1.15, rng)
		var size: float = minf(mark.size, 0.5) if kind == "extinguisher" else float(mark.size)
		if kind in SMALL_KINDS:
			size *= SMALL_SCALE
			var chip := planar + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * CHIP_SPREAD
			floor_view.call("stamp_material_debris", chip, kind, ATLASES.choose_frame(kind, true, rng), size * CHIP_SCALE, rng.randi_range(0, 3))
		floor_view.call("stamp_material_debris", planar, kind, frame, size, mark.turns)
