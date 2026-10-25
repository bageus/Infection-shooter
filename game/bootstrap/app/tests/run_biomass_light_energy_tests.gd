extends SceneTree
## Compare save-time lamp energy against real steady-state public fixture scenes.
const LAMP := preload("res://game/presentation/office_floor/public/props/planner_light.tscn")
const SAMPLER := preload("res://game/bootstrap/app/planning_biomass_light_bake.gd")
var failures := 0

class Controller extends Node:
	var local_lights_enabled := true
	var shadows_allowed := false
	var world_environment: WorldEnvironment


func _initialize() -> void: call_deferred("_run")


func _run() -> void:
	for kind in ["point", "linear", "rectangle"]:
		await _fixture_energy(kind)
		await _grid_pixels(kind)
	_fallback_spots()
	await process_frame
	await process_frame
	print("Biomass light energy tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _host() -> Node3D:
	var host := Node3D.new()
	root.add_child(host)
	var controller := Controller.new()
	controller.name = "PlanningLighting"
	host.add_child(controller)
	return host


func _fixture(host: Node3D, kind: String) -> Node3D:
	var fixture: Node3D = LAMP.instantiate()
	fixture.position = Vector3(4, 4, 4)
	fixture.call("configure_fixture", kind, false)
	host.add_child(fixture)
	fixture.call("set_local_lighting_enabled", true)
	fixture.call("set_authored_color", Color(0.8, 0.5, 0.25))
	return fixture


func _spots(fixture: Node3D) -> Array[SpotLight3D]:
	var result: Array[SpotLight3D] = []
	for node in fixture.find_children("*", "SpotLight3D", true, false): result.append(node)
	return result


func _snapshot(fixture: Node3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for spot in _spots(fixture):
		result.append({"position": spot.global_position, "direction": -spot.global_basis.z.normalized(),
			"energy": spot.light_energy, "color": spot.light_color, "range": spot.spot_range,
			"angle": cos(deg_to_rad(spot.spot_angle)), "cone": spot.spot_angle_attenuation, "attenuation": spot.spot_attenuation})
	return result


func _sampler(host: Node3D) -> RefCounted:
	var sampler := SAMPLER.new()
	sampler.configure(host, func() -> bool: return is_instance_valid(host))
	sampler.ambient = Color(0, 0, 0)
	return sampler


func _same_profile(sampler: RefCounted, expected: Array[Dictionary], label: String) -> void:
	var actual: Array = sampler.lamps
	_check(actual.size() == expected.size(), "Each real Spot has one baked contribution: " + label)
	for index in mini(actual.size(), expected.size()):
		_check(is_equal_approx(float(actual[index].energy), float(expected[index].energy)), "Baked energy equals steady runtime per Spot: " + label)
		for key in ["position", "direction", "color", "range", "angle", "cone", "attenuation"]:
			_check(actual[index][key] == expected[index][key], "Authored light input preserved (%s): %s" % [key, label])


func _total(entries: Array) -> float:
	var total := 0.0
	for entry: Dictionary in entries: total += float(entry.energy)
	return total


func _fixture_energy(kind: String) -> void:
	var host := _host()
	var fixture := _fixture(host, kind)
	var count := 1 if kind == "point" else (2 if kind == "linear" else 4)
	_check(_spots(fixture).size() == count, "Real %s fixture has its authored Spot count" % kind)
	for setting: Vector2 in [Vector2(1, 1), Vector2(2.75, 0.65), Vector2(0, 1.2)]:
		fixture.call("set_authored_energy", setting.x)
		fixture.set("energy_multiplier", setting.y)
		var expected := _snapshot(fixture)
		var sampler := _sampler(host)
		_same_profile(sampler, expected, "%s/%s" % [kind, setting])
		if setting == Vector2.ONE:
			print("Lamp energy %s: runtime %.4f, baked %.4f" % [kind, _total(expected), _total(sampler.lamps)])
	fixture.call("set_authored_energy", 1.7)
	fixture.set("energy_multiplier", 0.8)
	var nominal := _snapshot(fixture)
	fixture.call("set_budget_lit", false, false)
	await create_timer(0.4, true, false, true).timeout
	_check(_spots(fixture).all(func(spot: SpotLight3D) -> bool: return is_zero_approx(spot.light_energy)), "Out-of-budget real fixture has faded to zero: " + kind)
	_same_profile(_sampler(host), nominal, kind + " outside camera budget")
	fixture.call("set_budget_lit", true, false)
	fixture.call("set_runtime_light_active", false)
	_same_profile(_sampler(host), nominal, kind + " runtime inactive")
	fixture.call("set_runtime_light_active", true)
	fixture.call("configure_flicker", 1, 0.05)
	await create_timer(0.12, true, false, true).timeout
	_same_profile(_sampler(host), nominal, kind + " ignores transient flicker")
	host.free()


func _grid_pixels(kind: String) -> void:
	var host := _host()
	var fixture := _fixture(host, kind)
	fixture.call("set_authored_energy", 0.6)
	fixture.set("energy_multiplier", 0.5)
	var expected := _snapshot(fixture)
	var sampler := _sampler(host)
	var point := Vector3(4, 0.025, 4)
	var color := Color(0, 0, 0)
	# Same diffuse model, but energy/geometry comes from actual runtime SpotLights.
	for spot: Dictionary in expected: color += SAMPLER.diffuse(spot, point)
	var image: Image = await sampler.sample(Vector2i.ZERO, 0.0)
	_check(image != null, "Save-time grid produced: " + kind)
	if image != null:
		var pixel := image.get_pixel(16, 16)
		var error := maxf(absf(pixel.r - color.r), maxf(absf(pixel.g - color.g), absf(pixel.b - color.b)))
		_check(error <= 1.0 / 255.0 + 0.00001, "RGB8 light grid uses runtime-distributed energy without overexposure: " + kind)
	host.free()


func _fallback_spots() -> void:
	var host := _host()
	var fixture := Node3D.new()
	host.add_child(fixture)
	fixture.add_to_group("budget_lights")
	for energy in [0.2, 0.4]:
		var spot := SpotLight3D.new()
		spot.light_energy = energy
		fixture.add_child(spot)
	_same_profile(_sampler(host), _snapshot(fixture), "legacy fixture without authored-energy API")
	fixture.free()
	var empty := Node3D.new()
	host.add_child(empty)
	empty.add_to_group("budget_lights")
	_check(_sampler(host).lamps.is_empty(), "Budget entry without SpotLights remains harmless")
	host.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
