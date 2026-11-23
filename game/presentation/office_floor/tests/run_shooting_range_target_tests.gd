extends SceneTree
## A shot drops the shooting range target flat, leaves the base in place, and it stands up after 10 seconds.

const TARGET := preload("res://game/presentation/office_floor/public/props/shooting_range_target.tscn")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var target := TARGET.instantiate() as Node3D
	root.add_child(target)
	target.global_position = Vector3(2, 0, 3)
	await process_frame
	var hinge := target.find_child("Hinge", false, false) as Node3D
	var base := target.find_child("Base", false, false) as Node3D
	_check(hinge != null and base != null, "hinge and base exist")
	var base_start := base.global_position
	_check(target.take_projectile_hit(10.0, Vector3(2, 1, 3), Vector3.BACK, Vector3.FORWARD, "AK"), "hit is absorbed")
	await create_timer(0.5).timeout
	_check(hinge.global_basis.y.dot(Vector3.UP) < 0.1, "post lies flat after the hit")
	_check(hinge.global_position.is_equal_approx(target.global_position + Vector3(0, 0.105, 0.02)), "hinge stays at the base top")
	_check(base.global_position.is_equal_approx(base_start), "base stays in place")
	target.take_projectile_hit(10.0, Vector3(2, 1, 3), Vector3.BACK, Vector3.FORWARD, "AK")
	await create_timer(10.5).timeout
	_check(hinge.global_basis.y.dot(Vector3.UP) > 0.95, "post stands up again after 10 seconds")
	target.queue_free()
	await process_frame
	print("Shooting range target tests: %d failure(s)." % failures)
	quit(failures)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + label)
