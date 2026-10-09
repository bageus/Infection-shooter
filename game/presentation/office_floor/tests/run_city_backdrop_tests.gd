extends SceneTree

const CITY := preload("res://game/presentation/office_floor/public/city_backdrop.tscn")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var city := CITY.instantiate() as Node3D
	root.add_child(city)
	await process_frame
	_check(city.get_child_count() == 4, "Four directional batches")
	var count := 0
	for child in city.get_children():
		var batch := child as MultiMeshInstance3D
		_check(batch != null, "Only render batches, no physics")
		if batch == null:
			continue
		_check(batch.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "No shadow allocation")
		var instances := batch.multimesh
		count += instances.instance_count
		for index in instances.instance_count:
			var transform: Transform3D = city.building_transforms[count - instances.instance_count + index]
			var half := transform.basis.get_scale() * 0.5
			var center := transform.origin
			var outside := absf(center.x) - half.x >= 69.99 or absf(center.z) - half.z >= 59.99
			_check(outside, "Building keeps 30m gap outside 80x60 location")
			_check(center.y - half.y <= -64.9, "Building continues below playable floor")
	_check(count == 32, "Bounded 32 building budget")
	var second := CITY.instantiate() as Node3D
	root.add_child(second)
	await process_frame
	for index in 32:
		_check(city.building_transforms[index].is_equal_approx(second.building_transforms[index]), "Deterministic restart")
	city.queue_free()
	second.queue_free()
	await process_frame
	print("City backdrop failures: ", failures)
	quit(0 if failures == 0 else 1)

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)
