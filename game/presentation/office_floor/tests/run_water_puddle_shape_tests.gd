extends SceneTree
## Spilled water puddles get irregular, per-puddle outlines instead of identical circles.

const BURST := preload("res://game/presentation/office_floor/water_bottle_burst.gd")
var failures := 0


func _init() -> void:
	_run()
	print("Water puddle shape tests: %d failure(s)." % failures)
	quit(failures)


func _run() -> void:
	var first := _outline_for_seed(1)
	var second := _outline_for_seed(2)
	_check(first.size() == BURST.OUTLINE_POINTS, "outline has the configured point count")
	_check(first[0].distance_to(second[0]) > 0.001 or first[5].distance_to(second[5]) > 0.001, "different seeds give different outlines")

	var worst_ratio := INF
	for seed_value in range(1, 31):
		var outline := _outline_for_seed(seed_value)
		var near := INF
		var far := 0.0
		for point in outline:
			near = minf(near, point.length())
			far = maxf(far, point.length())
		worst_ratio = minf(worst_ratio, far / maxf(near, 0.0001))
	_check(worst_ratio > 1.25, "every sampled puddle is clearly non-circular (worst far/near %.2f)" % worst_ratio)

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var mesh := BURST.puddle_mesh(rng, 0.5)
	_check(mesh.get_surface_count() == 1, "puddle mesh has one surface")
	var vertices := mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	_check(vertices.size() == BURST.OUTLINE_POINTS + 1, "puddle mesh has centre plus rim vertices")
	var flat := true
	for vertex in vertices:
		flat = flat and absf(vertex.y) < 0.0001
	_check(flat, "puddle mesh lies flat on the floor plane")


func _outline_for_seed(seed_value: int) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return BURST.puddle_outline(rng, 0.5)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)
		failures += 1
