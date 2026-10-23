extends SceneTree

const WINDOW := preload("res://game/presentation/office_floor/public/structural/window_double.tscn")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var windows: Array[Node3D] = []
	for i in 3:
		var window := WINDOW.instantiate() as Node3D
		window.position = Vector3(i * 2.0, 0.0, 0.0)
		host.add_child(window)
		windows.append(window)
	var far := WINDOW.instantiate() as Node3D
	far.position = Vector3(20.0, 0.0, 0.0)
	host.add_child(far)
	for i in 4:
		await process_frame
	var skirts := host.find_children("ExteriorFacadeSkirt", "MeshInstance3D", false, false)
	_check(skirts.size() == 1, "All windows share one skirt mesh")
	if skirts.size() == 1:
		var skirt := skirts[0] as MeshInstance3D
		_check(skirt.mesh != null and skirt.mesh.get_surface_count() == 1, "Skirt is a single surface")
		var bounds := skirt.global_transform * skirt.mesh.get_aabb()
		var frame := windows[0].find_child("frame", true, false) as MeshInstance3D
		var frame_bottom := (frame.global_transform * frame.get_aabb()).position.y
		_check(absf(bounds.position.y + 65.4) < 0.01, "Skirt reaches the city ground")
		_check(absf(bounds.end.y - frame_bottom) < 0.01, "Skirt meets the bottom of the window frames")
		_check(absf(bounds.end.x - (20.0 + 1.007)) < 0.05 and absf(bounds.position.x - (-0.997)) < 0.05, "Skirt spans the window footprint")
		# Two runs (three joined windows plus the far one): 4 walls of 4 vertices each.
		_check(skirt.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 32, "Neighbouring windows merge into one run")
		_check(skirt.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Skirt casts no shadow")
		_check(skirt.find_children("*", "CollisionObject3D", true, false).is_empty(), "Skirt is visual only")
		windows[1].queue_free()
		for i in 4:
			await process_frame
		_check(skirt.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 48, "Removing a window splits the run")
	host.queue_free()
	await process_frame
	print("exterior facade tests: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + label)
