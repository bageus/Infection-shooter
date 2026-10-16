extends SceneTree
const LIGHTING := preload("res://game/bootstrap/app/planning_lighting.gd")
const WALL := preload("res://game/presentation/office_floor/public/display_wall.gd")
const REAL_LAMP := preload("res://game/presentation/office_floor/public/props/planner_light.tscn")
var failures := 0
var stage: Node3D
var rig: Node3D
var camera: Camera3D
var controller: Node
var wall: Node
var lamps: Array[Node3D] = []
var displays: Array[Node3D] = []
var traces: Array[Dictionary] = []

class Lamp extends Node3D:
	var cost := 1
	var radius := 14.0
	var lit := true
	var shadow := false
	var writes := 0
	var local_enabled := false
	func _enter_tree() -> void:
		add_to_group("budget_lights")
	func get_light_cost() -> int:
		return cost
	func get_light_radius() -> float:
		return radius
	func set_budget_lit(on: bool, cast: bool) -> void:
		lit = on
		shadow = cast
		writes += 1
	func set_local_lighting_enabled(enabled: bool) -> void:
		local_enabled = enabled

class Display extends Node3D:
	var powered := true
	var tiled := false
	var screens: Array[Dictionary] = []
	var ticks := 0
	var registry: Node
	func tick(_seconds: float, _frames: Array[Vector4]) -> void:
		ticks += 1
	func _exit_tree() -> void:
		if is_instance_valid(registry):
			registry.unregister_display(self)

class ObservedWall extends WALL:
	var view_checks := 0
	func _update_view(display: Node3D, view: Camera3D) -> void:
		view_checks += 1
		super._update_view(display, view)


func _initialize() -> void:
	call_deferred("_run")


func _fixture() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	rig = Node3D.new()
	stage.add_child(rig)
	camera = Camera3D.new()
	rig.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 100.0
	camera.position = Vector3(0, 20, 0)
	camera.rotation_degrees.x = -90
	camera.current = true
	controller = LIGHTING.new()
	stage.add_child(controller)
	controller.set_process(false)
	controller.local_lights_enabled = true
	wall = ObservedWall.new()
	stage.add_child(wall)
	wall.set_process(false)
	for index in 36:
		var lamp := Lamp.new()
		stage.add_child(lamp)
		lamp.position = Vector3(index * 1.1, 3, .03 * index)
		lamps.append(lamp)
	for index in 24:
		var display := Display.new()
		var holder := Node3D.new()
		stage.add_child(holder)
		holder.add_child(display)
		display.position = Vector3(index * .4, 1, .01 * index)
		_add_screen(display)
		display.registry = wall
		wall.register_display(display)
		displays.append(display)
	_step("initial")
	_settle()


func _add_screen(display: Node3D) -> SpotLight3D:
	var light := SpotLight3D.new()
	display.add_child(light)
	display.screens.append({"light": light, "dynamic": true})
	return light


func _run() -> void:
	_fixture()
	_idle()
	_lamp_changes()
	_display_changes()
	await _camera_changes()
	_real_flicker()
	stage.free()
	await process_frame
	if "--trace" in OS.get_cmdline_user_args():
		print("LIGHT_BUDGET_TRACE ", JSON.stringify(traces))
	print("Light budget cache tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _step(label: String = "") -> void:
	controller._process(.2)
	wall._process(.2)
	if not label.is_empty():
		var bits: Array = []
		var screens: Array = []
		for lamp in lamps:
			if is_instance_valid(lamp):
				bits.append([lamp.lit, lamp.shadow])
		for display in displays:
			if is_instance_valid(display):
				for screen: Dictionary in display.screens:
					screens.append([screen.light.visible, screen.light.shadow_enabled])
		traces.append({"step": label, "lamps": bits, "screens": screens})


func _settle() -> void:
	for index in 3:
		_step()


func _idle() -> void:
	_settle()
	var ticks: int = displays[0].ticks
	for lamp in lamps:
		if is_instance_valid(lamp):
			lamp.writes = 0
	wall.view_checks = 0
	for index in 20:
		_step()
	_expect(_writes() == 0, "Stationary lamps do not reapply decisions")
	_expect(wall.view_checks == 0, "Stationary screens do not rebuild light/view decisions")
	_expect(displays[0].ticks > ticks, "Animation continues while light decisions are cached")


func _lamp_changes() -> void:
	_expect(lamps[0].lit and lamps[0].shadow and not lamps[-1].lit, "Nearest lights win original budgets")
	lamps[0].position.x = 1000
	_step("lamp moved")
	_expect(not lamps[0].lit, "Moved lamp leaves the frustum")
	lamps[0].radius = 2000
	_step("lamp radius")
	lamps[1].cost = 4
	_step("lamp cost")
	var cost := 0
	var shadows := 0
	for lamp in lamps:
		cost += lamp.cost if lamp.lit else 0
		shadows += lamp.cost if lamp.shadow else 0
	_expect(cost <= 28 and shadows <= 6, "Changed fixture costs respect both budgets")
	controller.set_shadows_allowed(false)
	_step("lamp shadows off")
	_expect(not lamps.any(func(lamp: Node3D) -> bool: return lamp.shadow), "Shadow permission changes immediately")
	controller.set_shadows_allowed(true)
	var added := Lamp.new()
	stage.add_child(added)
	added.position = Vector3(-.1, 3, 0)
	lamps.append(added)
	_step("lamp added")
	_expect(added.lit, "Late group members participate")
	added.free()
	_step("lamp removed")
	controller.local_lights_enabled = false
	_step("local lights off")
	_expect(lamps[1].local_enabled == false, "Application off reaches existing lamps")
	controller.local_lights_enabled = true
	_step("local lights on")
	_idle()


func _display_changes() -> void:
	var first: Node3D = displays[0]
	first.powered = false
	wall.update_animation(first)
	_step("display off")
	_expect(not first.screens[0].light.visible, "Powered-off display glow is off")
	first.powered = true
	wall.update_animation(first)
	first.position.x = 1000
	_step("display moved away")
	_expect(not first.screens[0].light.visible, "Moving a display updates its glow budget")
	first.screens[0].light.visible = true
	wall.update_animation(first)
	_step("reconfigured offscreen display")
	_expect(not first.screens[0].light.visible, "Configure reapplies culling even when power is unchanged")
	var ticks: int = first.ticks
	_step()
	_expect(first.ticks == ticks, "Far offscreen animations remain culled")
	first.position.x = 0
	_step("display returned")
	_expect(first.ticks > ticks, "Returning animations catch up")
	var light := _display_geometry_changes(first)
	wall.set_shadows_allowed(false)
	_step("screen shadows off")
	_expect(not light.shadow_enabled, "Display shadow setting takes effect")
	wall.set_shadows_allowed(true)
	first.powered = false
	_step("direct power change")
	_expect(not light.visible, "Power changes are detected without configure callback")
	first.powered = true
	wall.update_animation(first)
	_step("display on")
	var removed: Node3D = displays.pop_back()
	removed.free()
	_step("display removed")
	_idle()


func _display_geometry_changes(first: Node3D) -> SpotLight3D:
	var parent := first.get_parent()
	parent.hide()
	_step("hidden parent")
	_expect(not first.screens[0].light.visible, "Ancestor visibility invalidates glow")
	parent.show()
	_step("shown parent")
	var light: SpotLight3D = first.screens[0].light
	light.position.x = 1000
	_step("screen light offset")
	_expect(not light.visible, "Independent glow position invalidates selection")
	light.position.x = 0
	var extra := _add_screen(first)
	_step("screen added")
	first.screens.pop_back()
	extra.free()
	_step("screen removed")
	return light


func _camera_changes() -> void:
	for property in ["size", "near", "far", "h_offset", "v_offset"]:
		camera.set(property, float(camera.get(property)) + 1.0)
		_camera_step("camera " + property)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera_step("perspective")
	camera.fov = 50
	_camera_step("fov")
	rig.position.x = 5
	_camera_step("camera parent")
	camera.rotation_degrees.z = 3
	_camera_step("camera rotation")
	root.size = Vector2i(800, 400)
	await process_frame
	_camera_step("viewport aspect")
	camera.clear_current(false)
	_camera_step("no camera")
	for display in displays:
		if is_instance_valid(display):
			_expect(display.screens[0].light.visible, "No-camera fallback preserves powered display glow")
	camera.current = true
	_camera_step("camera restored")
	var replacement := camera.duplicate() as Camera3D
	rig.add_child(replacement)
	replacement.current = true
	_camera_step("new camera")
	replacement.free()
	camera.current = true
	_camera_step("old camera restored")
	_idle()


func _camera_step(label: String) -> void:
	var before := _writes()
	var view_checks: int = wall.view_checks
	_step(label)
	_expect(_writes() > before, label + " invalidates lamp selection")
	_expect(wall.view_checks > view_checks, label + " invalidates screen selection")


func _real_flicker() -> void:
	var lamp := REAL_LAMP.instantiate()
	stage.add_child(lamp)
	lamp.set_process(false)
	lamp.set_local_lighting_enabled(true)
	lamp.configure_flicker(3, .2)
	lamp.get("_rng").seed = 12345
	controller.refresh_light_budget()
	var minimum := 1.0
	var maximum := 0.0
	for index in 600:
		lamp._process(1.0 / 60.0)
		minimum = minf(minimum, lamp.get("_flicker_factor"))
		maximum = maxf(maximum, lamp.get("_flicker_factor"))
	_expect(minimum < .2 and maximum > .8, "Real lamp blackout/recovery clock is independent of budget polling")
	lamp.free()


func _writes() -> int:
	var count := 0
	for lamp in lamps:
		if is_instance_valid(lamp):
			count += lamp.writes
	return count


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
