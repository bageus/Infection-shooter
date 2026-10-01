extends SceneTree

const MAIN := preload("res://game/bootstrap/app/main.tscn")
const LAMP := preload("res://game/presentation/office_floor/public/props/planner_light.tscn")
var _failures := 0
var _authored_msaa: int


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_authored_msaa = int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", Viewport.MSAA_DISABLED))
	var app := MAIN.instantiate()
	root.add_child(app)
	await process_frame
	_check_contact_settings(app, "startup")
	var controller: Node = app.get("planning_lighting")
	var overhead := app.get_node("GlobalOverheadLight") as DirectionalLight3D
	_check(overhead.get_parent() == app, "Global light belongs to composition root")
	_check(overhead.shadow_enabled and overhead.visible, "One global shadow source is active")
	_check(is_equal_approx(overhead.light_energy, 0.6), "Global energy is 0.6")
	_check(overhead.light_color == Color(0.88, 0.93, 1.0, 1.0), "Global color is cold")
	_check(is_equal_approx(overhead.light_specular, 0.3), "Specular budget is 0.3")
	var direction := -overhead.global_basis.z.normalized()
	_check(direction.y < 0.0 and is_equal_approx(rad_to_deg(direction.angle_to(Vector3.DOWN)), 25.0), "Global -Z points down, 25 degrees from vertical")
	_check(not controller.get("local_lights_enabled"), "Local lamps default off")
	var toggle := app.get_node("PlanningUI/Panel/VBox/LocalLights") as CheckButton
	_check(not toggle.button_pressed, "Planner toggle matches startup")
	for node: Node in get_nodes_in_group("planner_lights"):
		_check_lamp_off(node)
	_test_shadow_coverage(app, overhead)
	_test_local_toggle(app, controller, toggle)
	_test_disabled_map_loading(app, controller)
	var planner: Node = app.get("planning_mode")
	var basis_before := overhead.global_basis
	for cycle in range(5):
		planner.call("enter")
		controller.call("set_game_lighting", false)
		_check_contact_settings(app, "editor preview")
		controller.call("set_planning_mode", true)
		_check(overhead.visible and overhead.shadow_enabled and is_equal_approx(overhead.light_energy, 0.6), "Editor ambient keeps the global source")
		controller.call("set_game_lighting", true)
		_check_contact_settings(app, "game preview")
		planner.call("exit")
		_check_contact_settings(app, "planner exit")
		_check(overhead.global_basis == basis_before, "Planner does not rotate global light")
	var player := app.get_node("Gameplay/Player") as Node3D
	player.get_node("CameraRig").rotate_y(PI / 2.0)
	player.position += Vector3(32.0, 0.0, 32.0)
	app.get("chunk_streamer").call("_update_chunks", true)
	_check(overhead.global_basis == basis_before and overhead.visible, "Camera rotation/chunk changes leave global light active")
	for node: Node in get_nodes_in_group("planner_lights"):
		_check_lamp_off(node)
	app.free()
	paused = false
	await process_frame
	var restarted := MAIN.instantiate()
	root.add_child(restarted)
	_check_contact_settings(restarted, "restart")
	_check(not restarted.get("planning_lighting").get("local_lights_enabled"), "Scene restart restores local-off default")
	restarted.free()
	await process_frame
	print("Global lighting tests: %d failures" % _failures)
	quit(0 if _failures == 0 else 1)


func _test_local_toggle(app: Node, controller: Node, toggle: CheckButton) -> void:
	var lamp := LAMP.instantiate()
	app.get_node("PlanningObjects").add_child(lamp)
	lamp.set_authored_energy(7.0)
	var light := lamp.get_node("Light") as SpotLight3D
	light.shadow_enabled = true
	for mode in range(4):
		lamp.configure_flicker(mode, 0.2)
		_check_lamp_off(lamp)
		toggle.set_pressed(true)
		_check(controller.get("local_lights_enabled") and light.visible, "Toggle enables local sources")
		lamp.get("_rng").seed = 12345
		lamp._process(0.3)
		var factor: float = lamp.get("_flicker_factor")
		var elapsed: float = lamp.get("_elapsed")
		for cycle in range(5):
			toggle.set_pressed(false)
			lamp.set_runtime_light_active(true)
			lamp.set_planning_visual(true)
			lamp.set_authored_energy(7.0)
			lamp._process(1.0)
			_check_lamp_off(lamp)
			_check(is_equal_approx(lamp.get("_elapsed"), elapsed) and is_equal_approx(lamp.get("_flicker_factor"), factor), "Disabled flicker pauses without changing its phase")
			_check(is_equal_approx(lamp.get_authored_energy(), 7.0), "Global disable preserves authoring state")
			controller.call("set_local_lights_enabled", true)
			_check(toggle.button_pressed and light.visible, "API updates checkbox without a signal loop")
			_check(is_equal_approx(light.light_energy, 7.0 * 0.65 * factor), "Re-enable restores effective flickering energy once")
		lamp.set_runtime_light_active(false)
		_check_lamp_off(lamp)
		controller.call("set_local_lights_enabled", true)
		_check_lamp_off(lamp)
		lamp.set_runtime_light_active(true)
		_check(light.visible, "Runtime gate reopens only with global permission")
		var late := LAMP.instantiate()
		app.get_node("PlanningObjects").add_child(late)
		_check(late.get_node("Light").visible and is_equal_approx(late.get_node("Light").light_energy, 1.95), "Late map/new lamps inherit enabled setting")
		late.free()
		controller.call("set_local_lights_enabled", false)
	lamp.free()


func _test_disabled_map_loading(app: Node, controller: Node) -> void:
	var planner: Node = app.get("planning_mode")
	var data := {"version": 5, "objects": [
		{"scene": LAMP.resource_path, "light_energy": 7.0, "flicker_mode": 3},
		{"scene": LAMP.resource_path}
	]}
	for cycle in range(5):
		planner.get("objects").call("_apply_layout_data", data)
		_check_contact_settings(app, "old map reload")
		var lamps: Array[Node3D] = []
		for node: Node3D in planner.get("placed"):
			if node.is_in_group("planner_lights"):
				lamps.append(node)
		_check(lamps.size() == 2, "Old map loads while global lamps are disabled")
		for lamp: Node in lamps:
			_check_lamp_off(lamp)
		_check(is_equal_approx(lamps[0].get_authored_energy(), 7.0), "Disabled map loading preserves authored power")
		data = JSON.parse_string(JSON.stringify(planner.get("storage").call("_collect_layout_data")))
		controller.call("set_local_lights_enabled", true)
		_check(is_equal_approx(lamps[0].get_node("Light").light_energy, 4.55), "Saved disabled lamp recovers 7 * 0.65")
		_check(is_equal_approx(lamps[1].get_node("Light").light_energy, 1.95), "Legacy default recovers 3 * 0.65")
		controller.call("set_local_lights_enabled", false)


func _test_shadow_coverage(app: Node, overhead: DirectionalLight3D) -> void:
	var original := app.get_node("Gameplay/Player/CameraRig/Camera3D") as Camera3D
	var viewport := SubViewport.new()
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.fov = original.fov
	camera.rotation = original.rotation
	var max_depth := 0.0
	for size in [Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(2560, 1080)]:
		viewport.size = size
		for distance in [9.0, 24.0]:
			camera.position = original.position.normalized() * distance + Vector3.UP
			for corner in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), Vector2(size)]:
				var point: Variant = Plane(Vector3.UP, 0.0).intersects_ray(camera.global_position, camera.project_ray_normal(corner))
				_check(point != null, "Camera corner ray reaches floor")
				if point != null:
					var depth: float = (point - camera.global_position).dot(-camera.global_basis.z)
					max_depth = maxf(max_depth, depth)
	_check(max_depth < overhead.directional_shadow_max_distance * overhead.directional_shadow_fade_start, "Shadow distance covers visible floor before fade at both zoom limits")
	print("Maximum floor view depth: %.2f; shadow range: %.2f" % [max_depth, overhead.directional_shadow_max_distance])
	viewport.free()


func _check_contact_settings(app: Node3D, context: String) -> void:
	var world := app.get_node("WorldEnvironment") as WorldEnvironment
	var environment := world.environment
	var camera := app.get_node("Gameplay/Player/CameraRig/Camera3D") as Camera3D
	_check(camera.environment == null and camera.get_world_3d().environment == environment, "Game camera uses WorldEnvironment: " + context)
	_check(environment.ssao_enabled and is_equal_approx(environment.ssao_radius, 0.35)
		and is_equal_approx(environment.ssao_intensity, 0.6)
		and is_zero_approx(environment.ssao_light_affect), "SSAO survives " + context)
	_check(root.msaa_3d == _authored_msaa, "Game viewport retains authored MSAA: " + context)
	_check(int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")) == 2048, "Shadow atlas stays 2048: " + context)


func _check_lamp_off(lamp: Node) -> void:
	var light := lamp.get_node("Light") as SpotLight3D
	_check(not light.visible and is_zero_approx(light.light_energy), "Global/runtime disable removes light and shadow contribution")
	_check(not lamp.is_processing(), "Disabled lamps do not process flicker")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
