extends SceneTree
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const AMBIENCE := preload("res://game/presentation/office_floor/server_ambience.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	for model in ["03_server_rack.glb", "03_server_rack2.glb", "03_server_rack3.glb"]:
		var prop := PROP.instantiate() as RigidBody3D
		prop.set("model_path", "res://models/objects/enviroments/03/" + model)
		stage.add_child(prop)
		var fan := prop.get_node_or_null("ServerFans") as AudioStreamPlayer3D
		_check(fan != null, "A real server rack attaches its fan: " + model)
		if fan != null:
			_check(fan.stream.loop and absf(fan.stream.get_length()-2.62) < .02, "Fan is trimmed by .3 seconds and crossfaded by .08 seconds")
			_check(fan.max_distance == 4 and fan.unit_size == 1 and fan.attenuation_model == AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE, "Fan fades with distance and is inaudible beyond four meters")
			_check(fan.bus == &"SFX" and fan.playing == (DisplayServer.get_name() != "headless") and fan.position.y == 1.0, "Fan is attached to the prop, uses SFX and plays continuously")
			# Damage, rather than just a direct helper call, must stop the fan.
			prop.call("take_projectile_hit", 100000.0, prop.global_position, Vector3.UP, Vector3.FORWARD, "GRENADE")
			await process_frame
			_check(not fan.playing or prop.is_queued_for_deletion(), "Destroyed server does not keep humming")
	var ordinary := Node3D.new()
	stage.add_child(ordinary)
	AMBIENCE.attach(ordinary, "05_computer_tower_destructible.glb")
	_check(ordinary.get_node_or_null("ServerFans") == null, "Non-server props do not acquire the server loop")
	stage.queue_free()
	await process_frame
	await process_frame
	await create_timer(.1).timeout # Native audio releases stopped streams asynchronously.
	print("Server audio tests: %d failures" % failures)
	quit(failures)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
