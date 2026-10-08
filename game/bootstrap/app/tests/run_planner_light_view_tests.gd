extends SceneTree
const MAIN := preload("res://game/bootstrap/app/main.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := MAIN.instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	var planner: Node = stage.get("planning_mode")
	planner.enter()
	var controls: Node = planner.controls
	controls._show_lighting_catalog()
	var view: RefCounted = controls.light_view
	var camera: Camera3D = planner.camera
	var original := camera.global_transform
	var projection := camera.projection
	view.button.button_pressed = true
	_check(view.active and camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Lights toggle enables overhead projection")
	_check(camera.project_ray_normal(root.get_visible_rect().size * 0.5).dot(Vector3.DOWN) > 0.999, "Overhead rays point straight down")
	_check(view.forward().length() > 0.99, "WASD has a stable horizontal forward vector")
	var size_before := camera.size
	planner._zoom_camera(-2.5)
	_check(camera.size < size_before and is_equal_approx(camera.global_position.y, 24.0), "Wheel zooms overhead without moving below lamps")
	var center := root.get_visible_rect().size * 0.5
	for index in 3:
		planner.objects._on_palette_selected(index)
		_check(controls.light_defaults.visible, "Palette lamp exposes editable fields immediately")
		controls.default_light_height.value = 3.5 + index * 0.25
		controls.default_light_energy.value = 5.0 + index
		controls.default_light_angle.value = 40.0 + index
		controls.default_light_color.color = Color(0.4, 0.6, 0.8)
		controls.default_light_color.color_changed.emit(controls.default_light_color.color)
		controls.default_flicker_step.value = 0.4
		_check(is_equal_approx(planner.objects.preview.global_position.y, controls.default_light_height.value), "Preview height updates before cursor movement")
		_check(is_equal_approx(planner.objects.preview.get_authored_energy(), controls.default_light_energy.value), "Preview brightness updates immediately")
		planner.objects._place_selected(center + Vector2(index * 50, 0))
		var lamp: Node3D = planner.objects.placed.back()
		_check(is_equal_approx(lamp.global_position.y, controls.default_light_height.value), "Overhead placement preserves configured height")
		_check(lamp.get_authored_color().is_equal_approx(controls.default_light_color.color), "Placed lamp keeps palette color")
		_check(is_equal_approx(lamp.get_node("Light").spot_angle, controls.default_light_angle.value), "Placed lamp keeps palette cone")
		_check(lamp.get_fixture_config().shape == controls.fixtures.SHAPES[index], "Each palette shape is preserved")
		planner.objects._reset_selection()
		planner.objects._select(lamp)
		_check(controls.fixtures.selected_panel.visible and not controls.light_defaults.visible, "Installed lamp shows its own settings")
		var height_before := lamp.global_position.y
		controls.fixtures.selected_height.value = height_before + 0.25
		_check(is_equal_approx(lamp.global_position.y, height_before + 0.25), "Installed lamp height remains editable")
		planner.edit_history.undo()
		_check(is_equal_approx(lamp.global_position.y, height_before), "Undo restores height")
	view.button.button_pressed = false
	_check(camera.global_transform.is_equal_approx(original) and camera.projection == projection, "Normal view restores original camera")
	var lamp: Node3D = planner.objects.selected
	controls.fixtures.selected_energy.value = 9.0
	_check(is_equal_approx(lamp.get_authored_energy(), 9.0), "Normal view can refine installed brightness")
	view.button.button_pressed = true
	camera.global_position += Vector3(4, 0, -3)
	view.button.button_pressed = false
	_check(camera.global_position.is_equal_approx(original.origin + Vector3(4, 0, -3)), "Returning to normal view preserves overhead panning")
	view.button.button_pressed = true
	controls._show_structure_catalog()
	_check(not view.active and not view.button.visible and camera.projection == projection, "Leaving Lights restores normal projection")
	controls._show_lighting_catalog()
	view.button.button_pressed = true
	planner.exit()
	_check(not view.active and camera.projection == projection, "Exiting planner restores game camera projection")
	planner.enter()
	_check(not view.active, "Reopening planner starts in normal view")
	planner.exit()
	stage.queue_free()
	await process_frame
	print("Planner light view tests: %d failure(s)." % failures)
	quit(1 if failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
