extends SceneTree
## Lamp fixtures cover their whole surface, cast no shadow themselves, share the
## renderer's light budget, and desk lamps / elevator indicators emit light.

const LAMP := preload("res://game/presentation/office_floor/public/props/planner_light.tscn")
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const ELEVATOR := preload("res://game/presentation/office_floor/public/structural/elevator_door.tscn")
const LIGHTING := preload("res://game/bootstrap/app/planning_lighting.gd")
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_fixture_lights()
	_test_budget()
	await _test_desk_lamp()
	await _test_elevator()
	print("Lamp lighting tests: %d failure(s)." % _failures)
	quit(0 if _failures == 0 else 1)


func _lamp(shape: String, pos := Vector3.ZERO) -> Node3D:
	var lamp := LAMP.instantiate() as Node3D
	root.add_child(lamp)
	lamp.position = pos
	lamp.call("configure_fixture", shape, true)
	lamp.call("set_local_lighting_enabled", true)
	return lamp


func _lights_of(lamp: Node3D) -> Array[SpotLight3D]:
	var found: Array[SpotLight3D] = []
	for child in lamp.get_children():
		if child is SpotLight3D:
			found.append(child)
	return found


func _test_fixture_lights() -> void:
	var expected := {"point": 1, "linear": 2, "rectangle": 4}
	for shape: String in expected:
		var lamp := _lamp(shape)
		var lights := _lights_of(lamp)
		_check(lights.size() == expected[shape], "%s fixture has %d spot lights, got %d" % [shape, expected[shape], lights.size()])
		_check(int(lamp.call("get_light_cost")) == lights.size(), "%s light cost matches its lights" % shape)
		var span_x := 0.0
		var span_z := 0.0
		for light in lights:
			span_x = maxf(span_x, absf(light.position.x) * 2.0)
			span_z = maxf(span_z, absf(light.position.z) * 2.0)
			_check(light.light_energy > 0.0, "%s light is lit" % shape)
		if shape == "linear":
			_check(span_x >= 0.7 and span_z < 0.01, "linear lights spread along the long side")
		if shape == "rectangle":
			_check(span_x >= 0.4 and span_z >= 0.3, "rectangle lights cover both sides")
		for mesh_name in ["Housing", "Diffuser"]:
			var mesh := lamp.get_node("Fixture/" + mesh_name) as MeshInstance3D
			_check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s of the %s fixture casts no shadow" % [mesh_name, shape])
		# Cone changes of the main light reach the other lights.
		var main := lamp.get_node("Light") as SpotLight3D
		main.spot_angle = 61.0
		lamp.call("sync_sub_lights")
		for light in lights:
			_check(is_equal_approx(light.spot_angle, 61.0), "%s lights follow the cone angle" % shape)
		lamp.free()


func _test_budget() -> void:
	var controller := LIGHTING.new()
	root.add_child(controller)
	controller.local_lights_enabled = true
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 10, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	camera.current = true
	var lamps: Array[Node3D] = []
	for index in range(40):
		var shape: String = ["point", "linear", "rectangle"][index % 3]
		lamps.append(_lamp(shape, Vector3(index * 2.0 - 40.0, 3.0, 0.0)))
	controller.refresh_light_budget()
	var cost := 0
	var shadows := 0
	var lit_far := 0
	for lamp in lamps:
		if lamp.call("get_budget_lit"):
			cost += int(lamp.call("get_light_cost"))
			for light in _lights_of(lamp):
				_check(light.visible, "A lit lamp shows all of its lights")
				if light.shadow_enabled:
					shadows += 1
			if absf(lamp.position.x) > 30.0:
				lit_far += 1
	_check(cost > 0 and cost <= LIGHTING.MAX_LIGHTS, "Lit lights stay within the budget (%d)" % cost)
	_check(shadows > 0 and shadows <= LIGHTING.MAX_SHADOW_LIGHTS, "Shadowed lights stay within the budget (%d)" % shadows)
	_check(lit_far == 0, "Lamps far from the camera are the ones dropped")
	_check(bool(lamps[20].call("get_budget_lit")), "The lamp under the camera is lit")
	_check(_lights_of(lamps[20])[0].shadow_enabled, "The lamp under the camera casts shadows")
	controller.set_shadows_allowed(false)
	for lamp in lamps:
		for light in _lights_of(lamp):
			_check(not light.shadow_enabled, "Shadow setting off disables lamp shadows")
	for lamp in lamps:
		lamp.free()
	camera.free()
	controller.free()


func _test_desk_lamp() -> void:
	var controller := LIGHTING.new()
	root.add_child(controller)
	var environment := WorldEnvironment.new()
	controller.add_child(environment)
	controller.setup(environment)
	controller.local_lights_enabled = true
	var prop := PROP.instantiate() as RigidBody3D
	prop.set("model_path", "res://models/objects/enviroments/05/05_lamp.glb")
	root.add_child(prop)
	await process_frame
	var glow := prop.find_child("BudgetLight", true, false) as OmniLight3D
	_check(glow != null, "Desk lamp carries its own light")
	if glow != null:
		controller.refresh_light_budget()
		_check(glow.visible and glow.light_energy > 0.0, "Desk lamp light is on with local lighting")
		_check(not glow.shadow_enabled, "Desk lamp light casts no shadow")
		controller.set_local_lights_enabled(false)
		_check(not glow.visible, "Desk lamp light follows the lighting setting")
	prop.free()
	controller.free()


func _test_elevator() -> void:
	var controller := LIGHTING.new()
	root.add_child(controller)
	var environment := WorldEnvironment.new()
	controller.add_child(environment)
	controller.setup(environment)
	controller.local_lights_enabled = true
	var door := ELEVATOR.instantiate() as Node3D
	root.add_child(door)
	var actor := Node3D.new()
	actor.position = Vector3(0, 0, -9.0)
	root.add_child(actor)
	var control := door.get_node("DoorController")
	control.call("configure_player", actor)
	for i in range(5):
		await physics_frame
	var glow := door.find_child("BudgetLight", true, false) as OmniLight3D
	_check(glow != null, "Elevator indicator has a light")
	if glow == null:
		return
	var housing := door.find_child("Indicator_Housing", true, false) as MeshInstance3D
	_check(not glow.visible, "Indicator light is off while the doors are shut")
	_check(not _lens_glows(housing), "Indicator lens is dark while the doors are shut")
	actor.position = Vector3(0, 0, -0.8)
	for i in range(100):
		await physics_frame
	_check(glow.visible, "Indicator light turns on when the doors are open")
	_check(_lens_glows(housing), "Indicator lens glows when the doors are open")
	_check(not _frame_glows(housing), "Only the lens glows, not the frame")
	actor.position = Vector3(0, 0, -9.0)
	for i in range(220):
		await physics_frame
	_check(not glow.visible, "Indicator light turns off after the doors close")
	door.free()
	actor.free()
	controller.free()


func _lens_glows(housing: MeshInstance3D) -> bool:
	var material := housing.get_surface_override_material(1) as BaseMaterial3D
	return material != null and material.emission_enabled


func _frame_glows(housing: MeshInstance3D) -> bool:
	var material := housing.get_surface_override_material(0) as BaseMaterial3D
	return material != null and material.emission_enabled


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
		print("FAIL: ", message)
