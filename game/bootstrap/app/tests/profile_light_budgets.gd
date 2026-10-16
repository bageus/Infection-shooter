extends SceneTree
## Manual CPU-only comparison of the existing periodic controller callbacks.
const LIGHTING := preload("res://game/bootstrap/app/planning_lighting.gd")
const WALL := preload("res://game/presentation/office_floor/public/display_wall.gd")
var controller: Node
var wall: Node
var camera: Camera3D
var stage: Node3D

class Lamp extends Node3D:
	var cost := 1
	var lit := true
	var shadow := false
	var writes := 0
	func _enter_tree() -> void:
		add_to_group("budget_lights")
	func get_light_cost() -> int:
		return cost
	func get_light_radius() -> float:
		return 14.0
	func set_budget_lit(on: bool, cast: bool) -> void:
		lit = on
		shadow = cast
		writes += 1
	func set_local_lighting_enabled(_enabled: bool) -> void:
		pass

class Display extends Node3D:
	var powered := true
	var screens: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _fixture() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	camera = Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0, 24, 18)
	camera.rotation_degrees.x = -55.0
	camera.current = true
	controller = LIGHTING.new()
	stage.add_child(controller)
	controller.set_process(false)
	controller.set("local_lights_enabled", true)
	wall = WALL.new()
	stage.add_child(wall)
	wall.set_process(false)
	for index in 362:
		var lamp := Lamp.new()
		lamp.cost = [1, 2, 4][index % 3]
		stage.add_child(lamp)
		lamp.position = Vector3((index % 20) * 3 - 30, 3, (index / 20) * 3 - 27)
	for index in 180:
		var display := Display.new()
		stage.add_child(display)
		display.position = Vector3((index % 18) * 2 - 18, 1, (index / 18) * 2 - 10)
		var light := SpotLight3D.new()
		display.add_child(light)
		display.screens.append({"light": light, "dynamic": false})
		wall.displays.append(display)


func _run() -> void:
	_fixture()
	var fixture_memory := OS.get_static_memory_usage()
	for index in 5:
		controller.call("_process", 0.2)
		wall.call("_process", 0.2)
	var result := {"lamps": 362, "screens": 180, "iterations": 200, "configured_renderer": RenderingServer.get_current_rendering_method(), "display_server": DisplayServer.get_name(), "allocator_fixture_bytes": fixture_memory, "allocator_warm_bytes": OS.get_static_memory_usage()}
	for moving in [false, true]:
		var lamp_samples: Array[int] = []
		var screen_samples: Array[int] = []
		for index in 200:
			if moving:
				camera.position.x += .02
			var started := Time.get_ticks_usec()
			controller.call("_process", 0.2)
			lamp_samples.append(Time.get_ticks_usec() - started)
			started = Time.get_ticks_usec()
			wall.call("_process", 0.2)
			screen_samples.append(Time.get_ticks_usec() - started)
		result["moving" if moving else "stationary"] = {"lamps": _stats(lamp_samples), "screens": _stats(screen_samples)}
	result["allocator_end_bytes"] = OS.get_static_memory_usage()
	print("LIGHT_BUDGET_METRICS ", JSON.stringify(result))
	stage.free()
	quit()


func _stats(samples: Array[int]) -> Dictionary:
	samples.sort()
	var sum := 0
	for sample in samples:
		sum += sample
	return {"mean_usec": float(sum) / samples.size(), "p95_usec": samples[int(ceil(samples.size() * .95)) - 1], "max_usec": samples[-1]}
