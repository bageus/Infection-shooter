extends SceneTree

const WINDOW := preload("res://game/presentation/office_floor/public/structural/window_double.tscn")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var window := WINDOW.instantiate() as Node3D
	root.add_child(window)
	await process_frame
	await process_frame
	var facade := window.get_node_or_null("ExteriorFacade/ExteriorFacade") as MeshInstance3D
	_check(facade != null, "Exterior window builds a facade below its frame")
	if facade != null:
		var bounds := facade.global_transform * facade.get_aabb()
		var frame := window.find_child("frame", true, false) as MeshInstance3D
		var frame_bounds := frame.global_transform * frame.get_aabb()
		_check(absf(bounds.position.y + 65.4) < 0.01, "Facade reaches the city ground")
		_check(absf(bounds.end.y - frame_bounds.position.y) < 0.01, "Facade meets the bottom of the window frame")
		_check(absf(bounds.size.x - frame_bounds.size.x) < 0.01 and absf(bounds.size.z - frame_bounds.size.z) < 0.01, "Facade matches the window footprint")
		_check(facade.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Facade casts no shadow")
	_check(window.get_node("ExteriorFacade").find_children("*", "CollisionObject3D", true, false).is_empty(), "Facade is visual only")
	window.queue_free()
	await process_frame
	print("exterior facade tests: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + label)
