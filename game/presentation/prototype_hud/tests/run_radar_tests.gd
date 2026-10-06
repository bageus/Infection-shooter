extends SceneTree

class TestRadar:
	extends "res://game/presentation/prototype_hud/radar.gd"
	var draws := 0
	func _draw() -> void:
		draws += 1
		super._draw()

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
	stage.queue_free()
	await process_frame
	await process_frame
	print("Radar tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
