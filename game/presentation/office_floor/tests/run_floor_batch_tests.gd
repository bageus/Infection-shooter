extends SceneTree

const FLOOR := preload("res://game/presentation/office_floor/public/base_floor_renderer.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var floor_view := FLOOR.new()
	root.add_child(floor_view)
	_check(_count(floor_view) == 1200, "80x60 floor keeps all 1200 authored tiles")
	_check(floor_view.get_child_count() <= 160, "Spatial material batches replace individual tile nodes")

	for section: MultiMeshInstance3D in floor_view.get_children():
		_check(section.multimesh.instance_count <= 16, "Each initial lighting section covers at most sixteen tiles")
		_check(section.material_override != null, "Every batch retains its material variant")
	# Dummy rendering does not round-trip MultiMesh transforms. Geometry and
	# pixels are checked by this same suite in both required native CI passes.
	if DisplayServer.get_name() != "headless":
		_check(_covers(floor_view, Vector2(-39, -29)) and _covers(floor_view, Vector2(39, 29)), "Both floor corners remain covered")
		for section: MultiMeshInstance3D in floor_view.get_children():
			for index in section.multimesh.instance_count:
				var pose := section.multimesh.get_instance_transform(index)
				_check(is_equal_approx(pose.origin.y, .001) and is_equal_approx(pose.basis.y.length(), 1.0), "Tile height and thickness remain unchanged")
		await _render_equivalence(floor_view)
	var opening := Rect2(-1, -1, 2, 2)
	floor_view.set_stair_openings([opening])
	if DisplayServer.get_name() != "headless":
		_check(not _covers(floor_view, Vector2.ZERO), "Stair opening stays clear")
		_check(_covers(floor_view, Vector2(1.25, .25)) and _covers(floor_view, Vector2(-1.25, .25)), "Subtiles preserve floor alongside the opening")
		for section: MultiMeshInstance3D in floor_view.get_children():
			for index in section.multimesh.instance_count:
				var pose := section.multimesh.get_instance_transform(index)
				_check(not opening.has_point(Vector2(pose.origin.x, pose.origin.z)), "No instance centre covers the stair opening")
				var custom := section.multimesh.get_instance_custom_data(index)
				_check(is_equal_approx(custom.b, 1.0) or is_equal_approx(custom.b, .25), "Instances carry their tile scale for seam placement")
				var parent := Vector2(pose.origin.x, pose.origin.z) - Vector2(custom.r, custom.g)
				_check(is_equal_approx(fposmod(parent.x, 2.0), 1.0) and is_equal_approx(fposmod(parent.y, 2.0), 1.0), "Subtile seams follow their parent 2 m tile")
	var batches := floor_view.get_children()
	floor_view.set_stair_openings([opening])
	_check(floor_view.get_children() == batches, "Identical openings do not rebuild batches")
	floor_view.set_stair_openings([])
	_check(_count(floor_view) == 1200, "Removing stairs restores the original instance count")
	if DisplayServer.get_name() != "headless":
		_check(_covers(floor_view, Vector2(.25, .25)), "Removing stairs restores the original floor")
	floor_view.queue_free()
	await process_frame
	await process_frame
	print("Floor batch tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _count(view: Node) -> int:
	var total := 0
	for section: MultiMeshInstance3D in view.get_children():
		total += section.multimesh.instance_count
	return total

func _covers(view: Node, point: Vector2) -> bool:
	for section: MultiMeshInstance3D in view.get_children():
		var instances := section.multimesh
		for index in instances.instance_count:
			var pose := instances.get_instance_transform(index)
			var local := pose.affine_inverse() * Vector3(point.x, pose.origin.y, point.y)
			if absf(local.x) <= .999 and absf(local.z) <= .999:
				return true
	return false

func _render_equivalence(view: Node3D) -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 16
	root.add_child(camera)
	camera.look_at_from_position(Vector3(0, 14, 10), Vector3.ZERO)
	camera.current = true
	var light := DirectionalLight3D.new()
	root.add_child(light)
	light.rotation_degrees = Vector3(-70, -15, 0)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var batched := root.get_texture().get_image()
	var reference := Node3D.new()
	root.add_child(reference)
	for section: MultiMeshInstance3D in view.get_children():
		for index in section.multimesh.instance_count:
			var tile := MeshInstance3D.new()
			tile.mesh = section.multimesh.mesh
			tile.material_override = section.material_override
			tile.transform = section.multimesh.get_instance_transform(index)
			reference.add_child(tile)
	view.hide()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var separate := root.get_texture().get_image()
	var error := 0.0
	var samples := 0
	for y in range(0, batched.get_height(), 8):
		for x in range(0, batched.get_width(), 8):
			var a := batched.get_pixel(x, y)
			var b := separate.get_pixel(x, y)
			error += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			samples += 1
	_check(error / maxf(samples, 1) < .02, "Batched floor matches separate meshes in the active renderer")
	view.show()
	reference.queue_free()
	camera.queue_free()
	light.queue_free()
	await process_frame

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
