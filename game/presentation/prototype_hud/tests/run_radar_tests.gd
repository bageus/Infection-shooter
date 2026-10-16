extends SceneTree

class TestRadar:
	extends "res://game/presentation/prototype_hud/radar.gd"
	var draws := 0
	var markers: Array[Vector3] = []
	var capture_only := false
	func _draw() -> void:
		markers.clear()
		draws += 1
		super._draw()
	func _draw_blip(center: Vector2, radius: float, world_position: Vector3, color: Color, blip_radius: float) -> void:
		markers.append(world_position)
		if not capture_only:
			super._draw_blip(center, radius, world_position, color, blip_radius)

var failures := 0
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var actor := Node3D.new()
	actor.name = "Player"
	stage.add_child(actor)
	var enemies := Node3D.new()
	enemies.name = "Enemies"
	stage.add_child(enemies)
	var enemy := Node3D.new()
	enemies.add_child(enemy)
	enemy.position = Vector3(2, 0, 3)
	enemy.add_to_group(&"infected_alive")
	var radar := TestRadar.new()
	radar.player_path = NodePath("../Player")
	radar.enemies_path = NodePath("../Enemies")
	radar.size = Vector2(160, 160)
	stage.add_child(radar)
	radar.set_process(false)
	await process_frame
	var before := radar.draws
	for index in 60:
		radar.call("_process", .01)
		await process_frame
	if DisplayServer.get_name() != "headless":
		_check(radar.draws - before <= 13 and radar.draws > before, "Markers redraw at bounded cadence while the scene remains active")
	radar.hide()
	radar.call("_process", .2)
	_check(radar.get("_refresh_remaining") == 0.0, "Hidden radar stops refreshing and schedules an immediate resume")
	radar.show()
	radar.call("_process", .001)
	_check(float(radar.get("_refresh_remaining")) > 0, "Visible radar refreshes immediately")
	radar.size = Vector2(240, 200)
	await process_frame
	_check((radar.get("_background") as Control).size == radar.size, "Cached background follows radar resize")
	await _marker_selection(stage, radar, enemy)
	stage.queue_free()
	await process_frame
	await process_frame
	print("Radar tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _snapshot(radar: TestRadar) -> Array[Vector3]:
	if DisplayServer.get_name() == "headless":
		radar.markers.clear()
		radar.capture_only = true
		radar._draw_enemies(radar.size * .5, minf(radar.size.x, radar.size.y) * .42, 1.0)
		radar.capture_only = false
	else:
		radar.queue_redraw()
		await process_frame
		await process_frame
	return radar.markers.duplicate()


func _marker_selection(stage: Node3D, radar: TestRadar, alive: Node3D) -> void:
	var container := radar.enemies
	# Retained corpse, evicted corpse, severed limb and unrelated scene child.
	for index in 4:
		var extra := Node3D.new()
		extra.position = Vector3(4 + index, 0, 4)
		container.add_child(extra)
		extra.add_to_group(&"infected")
		if index == 1:
			extra.hide()
	var non_spatial := Node.new()
	container.add_child(non_spatial)
	non_spatial.add_to_group(&"infected_alive")
	var hidden := Node3D.new()
	container.add_child(hidden)
	hidden.add_to_group(&"infected_alive")
	hidden.hide()
	var removed := Node3D.new()
	container.add_child(removed)
	removed.add_to_group(&"infected_alive")
	removed.queue_free()
	var unrelated := Node3D.new()
	stage.add_child(unrelated)
	unrelated.add_to_group(&"infected_alive")
	_check(await _snapshot(radar) == [alive.global_position], "Only the visible live child produces a marker")
	alive.remove_from_group(&"infected_alive")
	_check((await _snapshot(radar)).is_empty(), "Retained corpse loses its marker without leaving the container")
	alive.add_to_group(&"infected_alive")
	_check(await _snapshot(radar) == [alive.global_position], "A newly registered live child appears")
	await _offscreen_and_visibility(stage, radar, alive)


func _offscreen_and_visibility(stage: Node3D, radar: TestRadar, alive: Node3D) -> void:
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.current = true
	var far := Node3D.new()
	radar.enemies.add_child(far)
	far.position = Vector3(5000, 0, 5000)
	far.add_to_group(&"infected_alive")
	_check(not camera.is_position_in_frustum(far.global_position), "Fixture is outside the camera frustum")
	_check(await _snapshot(radar) == [alive.global_position, far.global_position], "Offscreen and far live enemies retain their markers")
	(radar.enemies as Node3D).hide()
	_check((await _snapshot(radar)).is_empty(), "Hidden ancestor hides all markers")
	(radar.enemies as Node3D).show()
	_check((await _snapshot(radar)).size() == 2, "Showing the ancestor restores live markers")
	far.queue_free()
	_check(await _snapshot(radar) == [alive.global_position], "Queued live node produces no marker")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
