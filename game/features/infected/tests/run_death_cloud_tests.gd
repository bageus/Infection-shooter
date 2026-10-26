extends SceneTree
## Planner settings of an infected's death mutagen cloud: sanitizing, lifecycle and the no-cloud corpse.

const CLOUD := preload("res://game/features/infection_source/public/mutagen_cloud.tscn")
const SETTINGS := preload("res://game/features/infected/public/death_cloud_settings.gd")
const AUTHORING := preload("res://game/features/infected/infected_authoring.gd")

var failures := 0


class Absorber extends Node:
	func absorb_mutagen(seconds: float) -> float:
		return seconds * 5.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_defaults()
	_check_sanitize()
	var stage := Node3D.new()
	root.add_child(stage)
	await _check_timed_cloud(stage)
	await _check_untimed_cloud(stage)
	await _check_disabled_cloud(stage)
	stage.queue_free()
	await process_frame
	print("Death cloud tests: %d failure(s)." % failures)
	quit(failures)


func _check_defaults() -> void:
	var config := SETTINGS.sanitize(null)
	_expect(config == {"enabled": true, "time": "auto", "seconds": 14.0, "absorb": false, "units": 10.0}, "Default death cloud keeps today's behaviour.")


func _check_sanitize() -> void:
	_expect(SETTINGS.sanitize({"time": "none"})["time"] == "auto", "A cloud with no time limit and no absorption end falls back to auto.")
	_expect(SETTINGS.sanitize({"time": "none", "absorb": true})["time"] == "none", "A cloud may end by absorption alone.")
	_expect(SETTINGS.sanitize({"time": "bogus"})["time"] == "auto", "An unknown time mode falls back to auto.")
	_expect(SETTINGS.sanitize({"seconds": 999.0})["seconds"] == SETTINGS.SECONDS_MAX, "Duration is clamped.")
	_expect(SETTINGS.sanitize({"units": -4.0})["units"] == SETTINGS.UNITS_MIN, "Absorbed mutagen is clamped.")
	_expect(SETTINGS.sanitize({"units": "many"})["units"] == 10.0, "A non-number absorbed mutagen falls back to the default.")


func _check_timed_cloud(stage: Node3D) -> void:
	var cloud := _spawn(stage, Vector3.ZERO)
	SETTINGS.apply(cloud, SETTINGS.sanitize({"time": "manual", "seconds": 5.0}))
	cloud.call("activate")
	_expect(float(cloud.get("_lifetime_remaining")) == 5.0, "A manual duration sets the cloud's lifetime.")
	var depleted := [false]
	cloud.connect("depleted", func() -> void: depleted[0] = true)
	cloud.call("_physics_process", 5.5)
	_expect(depleted[0] and not cloud.visible, "A timed cloud ends when its time is up.")


func _check_untimed_cloud(stage: Node3D) -> void:
	var cloud := _spawn(stage, Vector3(10, 0, 0))
	SETTINGS.apply(cloud, SETTINGS.sanitize({"time": "none", "absorb": true, "units": 10.0}))
	cloud.call("activate")
	cloud.call("_physics_process", 100.0)
	_expect(cloud.visible, "An untimed cloud does not end by time.")
	var body := Absorber.new()
	stage.add_child(body)
	# 1.0 s of feeding gives 5 mutagen: half of the 10 threshold.
	cloud.call("_feed", body, 1.0)
	_expect(cloud.visible and float(cloud.get("_absorption_remaining")) == INF, "An absorption-ended cloud keeps feeding until its threshold.")
	cloud.call("_feed", body, 1.0)
	cloud.call("_physics_process", 5.0)
	_expect(not cloud.visible, "An untimed cloud ends once its threshold of mutagen is absorbed.")
	body.queue_free()


func _check_disabled_cloud(stage: Node3D) -> void:
	var owner := Node.new()
	stage.add_child(owner)
	var authoring := AUTHORING.new(owner)
	authoring.set_death_cloud({"enabled": false})
	_expect(not authoring.death_cloud()["enabled"], "A planner can switch an infected's death cloud off.")
	var cloud := _spawn(stage, Vector3(20, 0, 0))
	authoring.start_death_cloud(cloud)
	_expect(not bool(cloud.get("_active")), "An infected with no death cloud does not start one.")
	_expect(owner.has_meta(&"cloud_gone"), "A body with no death cloud is freed when hidden.")
	owner.queue_free()


func _spawn(stage: Node3D, at: Vector3) -> Area3D:
	var cloud := CLOUD.instantiate() as Area3D
	stage.add_child(cloud)
	cloud.global_position = at
	return cloud


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
