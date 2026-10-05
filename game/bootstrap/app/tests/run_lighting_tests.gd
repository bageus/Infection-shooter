extends SceneTree

const LAMP := preload("res://game/presentation/office_floor/public/props/planner_light.tscn")
const LIGHTING := preload("res://game/bootstrap/app/planning_lighting.gd")
const MAIN := preload("res://game/bootstrap/app/main.tscn")
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_ambient()
	_test_lamps()
	await _test_planner()
	print("Lighting tests: %d failures" % _failures)
	quit(0 if _failures == 0 else 1)


func _test_ambient() -> void:
	var world := WorldEnvironment.new()
	var authored := Environment.new()
	authored.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	authored.ambient_light_color = Color(0.2, 0.3, 0.5)
	authored.ambient_light_energy = 0.17
	world.environment = authored
	root.add_child(world)
	var controller := LIGHTING.new()
	root.add_child(controller)
	var selector := OptionButton.new()
	selector.add_item("Game")
	selector.add_item("Editor")
	root.add_child(selector)
	controller.setup(world, selector)
	for cycle in range(5):
		controller.set_planning_mode(true)
		selector.item_selected.emit(1)
		controller.set_planning_mode(true)
		controller.setup(world, selector)
		_check(is_equal_approx(world.environment.ambient_light_energy, 0.38), "Editor preview survives repeated entry/setup")
		selector.item_selected.emit(0)
		_check_ambient(world.environment, authored, "Game preview restores source/color/energy")
		selector.item_selected.emit(1)
		controller.set_planning_mode(false)
		controller.set_planning_mode(false)
		_check_ambient(world.environment, authored, "Repeated exit restores source/color/energy")
	_check(world.environment != authored, "Preview uses a runtime copy")
	_check(is_equal_approx(authored.ambient_light_energy, 0.17), "Shared scene resource remains authored")
	world.environment.ambient_light_energy = 0.24
	controller.set_planning_mode(true)
	controller.set_planning_mode(false)
	_check(is_equal_approx(world.environment.ambient_light_energy, 0.24), "A new session captures current game settings")
	controller.free()
	world.free()
	selector.free()


func _test_lamps() -> void:
	var lamp := LAMP.instantiate()
	root.add_child(lamp)
	lamp.set_local_lighting_enabled(true)
	lamp.set_process(false)
	var light := lamp.get_node("Light") as SpotLight3D
	_check(is_equal_approx(light.light_energy, 1.95), "Old scene defaults to 3 * 0.65")
	lamp.set_authored_energy(7.0)
	lamp.set_runtime_light_active(true)
	_check(is_equal_approx(light.light_energy, 4.55), "Constant/restored energy applies multiplier once")
	_test_flicker(lamp, light)
	lamp.set("energy_multiplier", 1.0)
	_check(is_equal_approx(light.light_energy, 7.0), "Multiplier 1 restores original authored power")
	lamp.set_authored_energy(0.0)
	_check(is_zero_approx(light.light_energy), "Zero authored energy remains off")
	lamp.free()
	var legacy := LAMP.instantiate()
	legacy.remove_meta("planning_light_energy")
	legacy.get_node("Light").light_energy = 6.0
	root.add_child(legacy)
	legacy.set_local_lighting_enabled(true)
	legacy.set_process(false)
	legacy.configure_flicker(0, 0.2)
	legacy.set_runtime_light_active(true)
	_check(is_equal_approx(legacy.get_authored_energy(), 6.0), "Legacy light captures raw scene energy once")
	_check(is_equal_approx(legacy.get_node("Light").light_energy, 3.9), "Legacy capture never compounds attenuation")
	legacy.free()


func _test_flicker(lamp: Node3D, light: SpotLight3D) -> void:
	for mode in range(1, 4):
		lamp.configure_flicker(mode, 0.2)
		lamp.get("_rng").seed = 12345
		var saw_dip := false
		var saw_blackout := false
		var saw_recovery := false
		for frame in range(600):
			lamp._process(1.0 / 60.0)
			var factor: float = lamp.get("_flicker_factor")
			_check(light.light_energy >= 0.0 and light.light_energy <= 4.55001, "Flicker stays inside effective base")
			saw_dip = saw_dip or factor < 0.99
			saw_blackout = saw_blackout or is_zero_approx(factor)
			saw_recovery = saw_recovery or (saw_blackout and factor > 0.8)
			var before := light.light_energy
			lamp.set_runtime_light_active(true)
			_check(is_equal_approx(light.light_energy, before), "Runtime restore preserves flicker phase")
		_check(saw_dip, "Each flicker mode modulates light")
		if mode == 3:
			_check(saw_blackout and saw_recovery, "Blackout mode turns off and recovers")
		var factor: float = lamp.get("_flicker_factor")
		lamp.set_authored_energy(8.0)
		_check(is_equal_approx(light.light_energy, 8.0 * 0.65 * factor), "Editing uses authored energy during flicker")
		lamp.configure_flicker(0, 0.2)
		_check(is_equal_approx(light.light_energy, 5.2), "Disabling flicker restores effective base immediately")
		lamp.set_authored_energy(7.0)


func _test_planner() -> void:
	var app := MAIN.instantiate()
	root.add_child(app)
	await process_frame
	var planner: Node = app.get("planning_mode")
	var controller: Node = app.get("planning_lighting")
	var world := app.get_node("WorldEnvironment") as WorldEnvironment
	var authored: Environment = world.environment.duplicate()
	_check(authored.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR, "Startup ambient explicitly uses color")
	_check(authored.ambient_light_color == Color(0.62, 0.68, 0.78, 1.0), "Startup ambient is cold")
	_check(is_equal_approx(authored.ambient_light_energy, 0.15), "Startup ambient energy is 0.15")
	_check(not authored.ssr_enabled, "First-pass lighting runs without SSR")
	_check(authored.tonemap_mode == Environment.TONE_MAPPER_FILMIC, "Filmic is preserved")
	for cycle in range(5):
		planner.call("enter")
		controller.call("set_game_lighting", false)
		controller.call("set_planning_mode", true)
		controller.call("set_game_lighting", true)
		_check_ambient(world.environment, authored, "Real planner game preview matches startup")
		controller.call("set_game_lighting", false)
		planner.call("exit")
		_check_ambient(world.environment, authored, "Real planner exit matches startup")
	controller.call("set_local_lights_enabled", true)
	_test_map_paths(planner)
	_test_colors(planner)
	_test_fixtures(planner)
	planner.call("enter")
	controller.call("set_game_lighting", false)
	app.free()
	paused = false
	await process_frame
	var restarted := MAIN.instantiate()
	root.add_child(restarted)
	_check_ambient((restarted.get_node("WorldEnvironment") as WorldEnvironment).environment, authored, "Scene restart during editor preview matches startup")
	restarted.free()
	await process_frame


func _test_map_paths(planner: Node) -> void:
	# Use the existing map DTO and real planner serialization/loading paths.
	var data := {"version": 5, "objects": [
		{"scene": LAMP.resource_path, "light_energy": 7.0, "flicker_mode": 2},
		{"scene": LAMP.resource_path, "light_energy": 0.0},
		{"scene": LAMP.resource_path},
		{"scene": LAMP.resource_path, "light_energy": 5.0, "energy_multiplier": 1.0}
	]}
	for cycle in range(5):
		planner.get("objects").call("_apply_layout_data", data)
		var lamps := _planner_lamps(planner)
		_check(lamps.size() == 4, "Legacy map without multiplier loads")
		var lamp: Node3D = lamps[0]
		lamp.set_process(false)
		_check(is_equal_approx(float(lamp.call("get_authored_energy")), 7.0), "Reload preserves authored energy")
		_check(is_equal_approx(lamp.get_node("Light").light_energy, 4.55), "Reload applies 0.65 once")
		_check(is_zero_approx(lamps[1].get_node("Light").light_energy), "Saved zero energy loads as zero")
		_check(is_equal_approx(float(lamps[2].call("get_authored_energy")), 3.0), "Missing energy retains scene default")
		_check(is_equal_approx(lamps[3].get_node("Light").light_energy, 5.0), "Explicit multiplier survives JSON round-trip")
		data = JSON.parse_string(JSON.stringify(planner.get("storage").call("_collect_layout_data")))
	var lamp: Node3D = _planner_lamps(planner)[0]
	lamp.call("_process", 0.3)
	planner.call("_select", lamp)
	planner.get("controls").call("_adjust_selected_light", 0.25)
	_check(is_equal_approx(float(lamp.call("get_authored_energy")), 7.25), "Planner adjustment ignores reduced instantaneous power")
	_check(is_equal_approx((planner.get("controls").get("light_level") as ProgressBar).value, 7.25), "Planner meter shows authored power")
	planner.get("edit_history").call("undo")
	_check(is_equal_approx(float(lamp.call("get_authored_energy")), 7.0), "Undo restores authored energy")
	planner.get("edit_history").call("duplicate_selected")
	var copy: Node3D = planner.get("selected")
	_check(is_equal_approx(copy.get_node("Light").light_energy, 4.55), "Duplicate calculates effective energy once")
	lamp.set("energy_multiplier", 1.0)
	planner.call("_select", lamp)
	planner.get("edit_history").call("duplicate_selected")
	copy = planner.get("selected")
	_check(is_equal_approx(copy.get_node("Light").light_energy, 7.0), "Duplicate preserves an explicit multiplier")
	(planner.get("controls").get("default_light_energy") as SpinBox).value = 4.0
	planner.get("controls").call("_apply_new_light_defaults", copy)
	_check(is_equal_approx(float(copy.call("get_authored_energy")), 4.0), "New-light defaults edit authoring state")
	_check(is_equal_approx(copy.get_node("Light").light_energy, 4.0), "New-light defaults use the existing multiplier once")


func _test_colors(planner: Node) -> void:
	var tint := Color(0.35, 0.65, 0.95)
	var data := {"version": 5, "objects": [
		{"scene": LAMP.resource_path, "light_energy": 7.0, "light_color": [tint.r, tint.g, tint.b], "flicker_mode": 2},
		{"scene": LAMP.resource_path}
	]}
	for cycle in range(5):
		planner.objects._apply_layout_data(data)
		var lamps := _planner_lamps(planner)
		_check(lamps[0].get_authored_color().is_equal_approx(tint), "Map RGB survives five JSON round trips")
		_check(lamps[1].get_authored_color().is_equal_approx(Color(1, 0.92, 0.78)), "Old map retains warm scene tint")
		data = JSON.parse_string(JSON.stringify(planner.storage._collect_layout_data()))
	var lamp: Node3D = _planner_lamps(planner)[0]
	lamp.set_process(false)
	lamp._process(0.3)
	var before: float = lamp.get_node("Light").light_energy
	var controls: Node = planner.controls
	var picker: ColorPickerButton = controls.selected_light_color
	planner._select(lamp)
	var stack_size: int = planner.edit_history.stack.size()
	picker.color_changed.emit(Color(0.9, 0.4, 0.2))
	picker.color_changed.emit(Color(0.8, 0.3, 0.1))
	picker.popup_closed.emit()
	_check(planner.edit_history.stack.size() == stack_size + 1, "A continuous color gesture creates one undo action")
	_check(is_equal_approx(lamp.get_node("Light").light_energy, before), "Editing color preserves flicker energy and phase")
	planner.edit_history.undo()
	_check(lamp.get_authored_color().is_equal_approx(tint), "Undo restores tint")
	_check(picker.color.is_equal_approx(tint), "Undo refreshes the tint swatch")
	planner.edit_history.duplicate_selected()
	var copy: Node3D = planner.selected
	_check(copy.get_authored_color().is_equal_approx(tint), "Duplicate preserves individual tint")
	copy.set_local_lighting_enabled(false)
	copy.set_authored_color(Color(0.7, 0.5, 0.3))
	copy.set_runtime_light_active(true)
	copy.set_local_lighting_enabled(true)
	_check(copy.get_node("Light").light_color.is_equal_approx(Color(0.7, 0.5, 0.3)), "Activation preserves color edited while disabled")
	planner.edit_history.record_deleted(copy)
	planner._delete_node(copy)
	planner.edit_history.undo()
	_check(_planner_lamps(planner).back().get_authored_color().is_equal_approx(Color(0.7, 0.5, 0.3)), "Undo deletion restores tint")
	controls.default_light_color.color = tint
	controls._apply_new_light_defaults(lamp)
	_check(lamp.get_authored_color().is_equal_approx(tint), "New-lamp defaults apply selected tint")
	var legacy := LAMP.instantiate()
	legacy.get_node("Light").light_color = Color(0.4, 0.8, 0.6)
	root.add_child(legacy)
	_check(legacy.get_authored_color().is_equal_approx(Color(0.4, 0.8, 0.6)), "Legacy per-instance Light color remains authored")
	legacy.free()
	var authored := Node3D.new()
	var saved := LAMP.instantiate()
	authored.add_child(saved)
	saved.owner = authored
	saved.set_authored_color(tint)
	var packed := PackedScene.new()
	_check(packed.pack(authored) == OK, "Authored lamp color packs into scene")
	var restored := packed.instantiate()
	root.add_child(restored)
	_check(restored.get_child(0).get_authored_color().is_equal_approx(tint), "Scene reload retains tint set before ready")
	authored.free()
	restored.free()


func _check_ambient(actual: Environment, expected: Environment, message: String) -> void:
	_check(actual.ambient_light_source == expected.ambient_light_source
		and actual.ambient_light_color == expected.ambient_light_color
		and is_equal_approx(actual.ambient_light_energy, expected.ambient_light_energy), message)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _planner_lamps(planner: Node) -> Array[Node3D]:
	var lamps: Array[Node3D] = []
	for node: Node3D in planner.get("placed"):
		if node.has_method("get_authored_energy"):
			lamps.append(node)
	return lamps



func _test_fixtures(planner: Node) -> void:
	var entries: Array = planner.catalog.lighting_catalog.filter(func(entry: Dictionary) -> bool: return entry.get("kind") == "light")
	_check(entries.size() == 3, "Lighting palette has three fixture shapes")
	for entry: Dictionary in entries:
		var fresh := LAMP.instantiate()
		planner.controls._configure_new_asset(fresh, entry)
		root.add_child(fresh)
		_check(fresh.get_fixture_config()["shape"] == entry["fixture_shape"], "Palette applies the chosen fixture")
		_check(fresh.fixture_visible_in_game, "New fixtures are visible in game by default")
		fresh.free()
	var records: Array = []
	for shape: String in ["point", "linear", "rectangle"]:
		records.append({"scene": LAMP.resource_path, "fixture_shape": shape,
			"fixture_visible_in_game": shape != "linear", "scale_x": 2.0, "scale_y": 0.5, "scale_z": 1.5,
			"light_energy": 7.0, "light_color": [0.2, 0.6, 0.9]})
	var data := {"version": 7, "objects": records}
	for cycle in range(3):
		planner.objects._apply_layout_data(data)
		var lamps := _planner_lamps(planner)
		_check(lamps.size() == 3, "All fixture shapes reload")
		for index in lamps.size():
			var lamp: Node3D = lamps[index]
			var config: Dictionary = lamp.call("get_fixture_config")
			_check(config["shape"] == records[index]["fixture_shape"], "JSON preserves fixture shape")
			_check(config["visible_in_game"] == records[index]["fixture_visible_in_game"], "JSON preserves game visibility")
			_check(lamp.scale.is_equal_approx(Vector3(2, 0.5, 1.5)), "JSON preserves model scale")
			_test_fixture_visibility(lamp)
		data = JSON.parse_string(JSON.stringify(planner.storage._collect_layout_data()))
	_test_fixture_edits(planner, _planner_lamps(planner)[1])
	planner.objects._apply_layout_data({"version": 6, "objects": [{"scene": LAMP.resource_path}]})
	var legacy: Node3D = _planner_lamps(planner)[0]
	_check(not bool(legacy.call("get_fixture_config")["visible_in_game"]), "Legacy maps keep invisible fixtures")
	legacy.call("configure_fixture", "unknown", false)
	_check(legacy.call("get_fixture_config")["shape"] == "point", "Unknown shape falls back safely")


func _test_fixture_visibility(lamp: Node3D) -> void:
	lamp.call("set_local_lighting_enabled", true)
	lamp.call("configure_flicker", 0, 0.2)
	var energy: float = lamp.get_node("Light").light_energy
	var shown: bool = lamp.call("get_fixture_config")["visible_in_game"]
	lamp.call("set_planning_visual", true)
	_check(lamp.get_node("Fixture").visible, "Every fixture can be seen and selected in the planner")
	lamp.call("set_planning_visual", false)
	_check(lamp.get_node("Fixture").visible == shown, "Leaving the planner applies authored visibility")
	_check(is_equal_approx(lamp.get_node("Light").light_energy, energy), "Hiding a body preserves its emitted light")
	var housing := lamp.get_node("Fixture/Housing") as MeshInstance3D
	var shape: String = lamp.call("get_fixture_config")["shape"]
	if shape == "point":
		_check(housing.mesh is CylinderMesh, "Point fixture has a round body")
	else:
		var size: Vector3 = (housing.mesh as BoxMesh).size
		_check(size.x > size.z * 5.0 if shape == "linear" else size.z > 0.5, "Linear and rectangular footprints differ")
	lamp.call("set_planning_visual", true)


func _test_fixture_edits(planner: Node, lamp: Node3D) -> void:
	planner._select(lamp)
	var fields = planner.controls.fixtures
	fields.selected_shape.select(2)
	fields.selected_shape.item_selected.emit(2)
	_check(lamp.call("get_fixture_config")["shape"] == "rectangle", "Inspector changes the selected shape")
	planner.edit_history.undo()
	_check(lamp.call("get_fixture_config")["shape"] == "linear", "Undo restores shape")
	fields.selected_visible.button_pressed = true
	_check(bool(lamp.call("get_fixture_config")["visible_in_game"]), "Inspector enables game visibility")
	planner.edit_history.undo()
	_check(not bool(lamp.call("get_fixture_config")["visible_in_game"]), "Undo restores body visibility")
	var scale_before := lamp.scale
	var energy_before: float = lamp.get_node("Light").light_energy
	planner.objects._scale_selected(Vector3(0.1, 0, 0))
	_check(is_equal_approx(lamp.scale.x, scale_before.x + 0.1), "Existing scale controls resize the lamp model")
	_check(is_equal_approx(lamp.get_node("Light").light_energy, energy_before), "Model resizing preserves authored brightness")
	planner.edit_history.undo()
	_check(lamp.scale.is_equal_approx(scale_before), "Undo restores model scale")
	planner.edit_history.duplicate_selected()
	var copy: Node3D = planner.selected
	_check(copy.call("get_fixture_config") == lamp.call("get_fixture_config"), "Duplicate preserves fixture settings")
	_check(copy.scale.is_equal_approx(lamp.scale), "Duplicate preserves fixture scale")
	copy.call("set_authored_color", Color.RED)
	var original_material := lamp.get_node("Fixture/Diffuser").material_override as StandardMaterial3D
	_check(original_material.albedo_color.is_equal_approx(lamp.call("get_authored_color")), "Fixture materials are isolated per instance")
	planner.edit_history.record_deleted(copy)
	planner._delete_node(copy)
	planner.edit_history.undo()
	var restored: Node3D = _planner_lamps(planner).back()
	_check(restored.call("get_fixture_config") == lamp.call("get_fixture_config"), "Delete Undo restores fixture settings")
	var authored := Node3D.new()
	var saved := LAMP.instantiate()
	saved.configure_fixture("rectangle", true)
	saved.scale = Vector3(2, 0.5, 1.5)
	authored.add_child(saved)
	saved.owner = authored
	var packed := PackedScene.new()
	_check(packed.pack(authored) == OK, "Fixture authoring state packs before ready")
	var baked := packed.instantiate()
	root.add_child(baked)
	var baked_lamp: Node3D = baked.get_child(0)
	_check(baked_lamp.call("get_fixture_config") == {"shape": "rectangle", "visible_in_game": true}, "Baked scenes retain fixture settings")
	_check(baked_lamp.scale.is_equal_approx(Vector3(2, 0.5, 1.5)), "Baked scenes retain model scale")
	baked.free()
	authored.free()
