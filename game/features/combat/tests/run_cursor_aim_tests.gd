extends SceneTree

const PISTOL := preload("res://game/features/combat/public/pistol.tscn")
const LAUNCHER := preload("res://game/features/combat/public/grenade_launcher.tscn")
const IMPACTS := preload("res://game/features/combat/public/impact_effects.gd")
const CASINGS := preload("res://game/features/combat/public/spent_casings.gd")
var failures := 0
var stage: Node3D
var gun: Node3D
var impacts: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var shooter := CharacterBody3D.new()
	stage.add_child(shooter)
	var pivot := Node3D.new()
	shooter.add_child(pivot)
	impacts = IMPACTS.new()
	stage.add_child(impacts)
	gun = PISTOL.instantiate()
	pivot.add_child(gun)
	gun.call("configure_world", stage, impacts)
	gun.position = Vector3(0, 1.2, 0)
	gun.set("spread_degrees", 0.0)
	gun.set_process(false)
	await physics_frame
	await _straight_targets()
	await _near_obstruction()
	await _ballistic(pivot)
	_casings(pivot, shooter)
	stage.queue_free()
	await process_frame
	await process_frame
	# The native audio mixer releases Ogg playback after the emitting nodes exit.
	await create_timer(0.2).timeout
	print("Cursor aim tests: %d failures" % failures)
	quit(failures)


func _straight_targets() -> void:
	for target in [Vector3(0, 0, -4), Vector3(5, 3, -3), Vector3(-2, 0.4, 1), Vector3(0, 4, 0)]:
		gun.call("aim_at", target)
		var muzzle: Node3D = gun.get_node("Muzzle")
		var axis := -muzzle.global_basis.z.normalized()
		_check(axis.dot((target - muzzle.global_position).normalized()) > .9999, "Barrel points at actual 3D cursor, including steep/downward target")
		gun.set("_cooldown_remaining", 0.0)
		_check(gun.call("try_fire_at", target), "A cursor shot is fired")
		var bullet := stage.get_child(stage.get_child_count() - 1)
		_check((bullet.get("_direction") as Vector3).dot(axis) > .9999, "Projectile leaves along visible barrel")
		bullet.queue_free()
		await process_frame


func _near_obstruction() -> void:
	# Cursor lies inside the barrel reach: the old muzzle-only ray skipped it.
	gun.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0))
	gun.call("aim_at", Vector3(0, 1.2, -5))
	var muzzle: Node3D = gun.get_node("Muzzle")
	var axis := -muzzle.global_basis.z.normalized()
	var reach := (muzzle.global_position - gun.global_position).dot(axis)
	_check(reach > .05, "Authored gun has a measurable barrel reach")
	var target := muzzle.global_position - axis * reach * .45
	var body := StaticBody3D.new()
	stage.add_child(body)
	body.global_position = target
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = Vector3.ONE * .045
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3.ONE * .045
	body.add_child(shape)
	await physics_frame
	await physics_frame
	gun.set("_cooldown_remaining", 0.0)
	gun.call("try_fire_at", target)
	var bullet := stage.get_child(stage.get_child_count() - 1)
	bullet.set_physics_process(false)
	bullet.call("_physics_process", .02)
	await process_frame
	_check(not is_instance_valid(bullet), "Object between grip and muzzle receives the shot")
	_check(not mesh.get_children().is_empty(), "Near obstacle receives a surface-attached impact")
	body.queue_free()
	await process_frame


func _ballistic(pivot: Node3D) -> void:
	var launcher := LAUNCHER.instantiate() as Node3D
	pivot.add_child(launcher)
	launcher.position = Vector3(0, 1.2, 0)
	launcher.call("configure_world", stage, impacts)
	for target in [Vector3(0, 0, -8), Vector3(1, 0, -2)]:
		launcher.set("_cooldown_remaining", 0.0)
		launcher.call("try_fire_at", target)
		var projectile := stage.get_child(stage.get_child_count() - 1)
		projectile.set_physics_process(false)
		var velocity: Vector3 = projectile.get("_velocity")
		var muzzle: Node3D = launcher.get_node("Muzzle")
		_check((-muzzle.global_basis.z.normalized()).dot(velocity.normalized()) > .9999, "Grenade initial velocity agrees with launcher barrel")
		var duration := clampf(Vector2(target.x - muzzle.global_position.x, target.z - muzzle.global_position.z).length() / 22.0, .42, 1.6)
		var endpoint := muzzle.global_position + velocity * duration + Vector3.DOWN * 8.5 * duration * duration
		_check(endpoint.distance_to(target) < .001, "Ballistic endpoint remains the cursor point")
		projectile.queue_free()
		await process_frame
	launcher.queue_free()


func _casings(pivot: Node3D, shooter: CollisionObject3D) -> void:
	var pool := CASINGS.new()
	pivot.add_child(pool)
	pool.call("configure_world", stage, impacts)
	var model := preload("res://game/features/combat/public/launcher_visual.gd").casing_model()
	pool.call("spawn_casing", model, Transform3D.IDENTITY, .01, shooter, &"", .7)
	var body := stage.get_child(stage.get_child_count() - 1)
	var collision := body.get_child(0) as CollisionShape3D
	_check(is_equal_approx(collision.shape.radius, .021), "Launcher casing collision is 30% smaller")
	var original := model.instantiate() as Node3D
	_check(body.get_child(1).scale.is_equal_approx(original.scale * 2.1), "Launcher casing visual is 30% smaller")
	original.free()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
