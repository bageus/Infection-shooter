extends SceneTree
## A 24-round/s weapon emits four AI noise pulses without losing any shots.
const MINIGUN := preload("res://game/features/combat/public/minigun.tscn")
var failures := 0

class Listener:
	extends Node
	var calls := 0
	var radius := 0.0
	func hear_noise(_where: Vector3, reach: float) -> void:
		calls += 1
		radius = reach


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var shooter := CharacterBody3D.new()
	stage.add_child(shooter)
	var pivot := Node3D.new()
	shooter.add_child(pivot)
	var listener := Listener.new()
	stage.add_child(listener)
	listener.add_to_group("infected_alive")
	var gun := MINIGUN.instantiate()
	pivot.add_child(gun)
	gun.call("configure_world", stage, null)
	gun.set_process(false)
	gun.set("_spin", 1.0)
	var fired := 0
	for _i in 24:
		if gun.call("try_fire_at", Vector3(0, 1, -20)):
			fired += 1
		gun.call("_process", 1.0 / 24.0)
	_check(fired == 24, "All 24 shots still fire (%d)" % fired)
	_check(listener.calls == 4, "24 shots emit exactly four AI pulses (%d)" % listener.calls)
	_check(listener.radius == 40.0, "Minigun uses its authored 40m AI radius")
	var expected := {"pistol":18.0, "uzi":22.0, "shotgun":30.0, "ak_rifle":32.0, "m4_rifle":28.0, "sniper_rifle":50.0, "minigun":40.0, "grenade_launcher":35.0}
	for id: String in expected:
		var scene := load("res://game/features/combat/public/%s.tscn" % id) as PackedScene
		var weapon := scene.instantiate()
		_check(weapon.get("shot_noise_radius") == expected[id], "Authored radius: " + id)
		_check(weapon.get("shot_noise_interval") == 0.25, "Four pulses/s is the default: " + id)
		weapon.free()
	stage.queue_free()
	await process_frame
	await process_frame
	print("Weapon noise tests: %d failures" % failures)
	quit(failures)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
