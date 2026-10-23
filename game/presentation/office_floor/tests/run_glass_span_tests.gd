extends SceneTree
## Glass partitions: the panes reach the full width of their frame, so two
## partitions set side by side leave no gap in the wall.

const SCENES := [
	"res://game/presentation/office_floor/public/structural/glass_partition_half.tscn",
	"res://game/presentation/office_floor/public/structural/glass_partition_blinds.tscn",
	"res://game/presentation/office_floor/public/structural/glass_wall_full.tscn",
]

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for path in SCENES:
		await _test_scene(path)
	print("Glass span tests: %d failure(s)." % failures)
	quit(failures)


func _test_scene(path: String) -> void:
	var scene := (load(path) as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	await process_frame
	var visual := scene.get_node("Visual") as Node3D
	var frame := visual.find_child("frame*", true, false) as MeshInstance3D
	var frame_span := _span(visual, frame)
	var name_of_scene := path.get_file()
	_expect(frame_span > 1.9, "%s: frame spans two metres (%.3f)." % [name_of_scene, frame_span])
	var panes := 0
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var pane := node as MeshInstance3D
		var lower := pane.name.to_lower()
		if pane.name.begins_with("GlassShard") or not ("glass" in lower or "blinds" in lower):
			continue
		var span := _span(visual, pane)
		if span == 0.0:
			continue # Empty copies that the model keeps for other layouts.
		panes += 1
		_expect(absf(span - frame_span) < 0.01, "%s: %s reaches the frame width." % [name_of_scene, pane.name])
	_expect(panes >= 1, "%s: has panes to span." % name_of_scene)
	scene.queue_free()
	await process_frame


func _span(visual: Node3D, node: MeshInstance3D) -> float:
	return ((visual.global_transform.affine_inverse() * node.global_transform) * node.get_aabb()).size.x


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		print("FAIL: " + message)
