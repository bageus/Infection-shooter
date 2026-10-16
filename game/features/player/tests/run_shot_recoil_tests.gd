extends SceneTree
const RECOIL := preload("res://game/features/player/shot_recoil.gd")
const PLAYER := preload("res://game/features/player/public/player.tscn")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var coarse := RECOIL.new()
	var fine := RECOIL.new()
	coarse.shot("SHOTGUN", Vector3.FORWARD)
	fine.shot("SHOTGUN", Vector3.FORWARD)
	var a := coarse.step(0.5)
	var b := Vector3.ZERO
	for i in 50:
		b += fine.step(0.01)
	_check(a.distance_to(b) < 0.00002 and absf(a.z - 0.02) < 0.00002, "20 mm shotgun recoil is frame-rate independent and opposite the shot")
	for weapon in RECOIL.DISTANCES:
		var state := RECOIL.new()
		for i in 100:
			state.shot(weapon, Vector3.RIGHT)
		_check(state.remaining.length() <= 0.080001 and state.remaining.x < 0.0, "Burst residue is capped in the shot direction")
		state.step(1.0)
		_check(state.remaining.is_zero_approx(), "Residual recoil expires without a forward spring")
	await _player()
	await create_timer(0.2).timeout
	print("Shot recoil tests: %d failures" % failures)
	quit(1 if failures else 0)

func _player() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var player = PLAYER.instantiate()
	stage.add_child(player)
	player.set_physics_process(false)
	player.gravity_acceleration = 0.0
	player.configure_world(stage, null)
	player.set("_aim_point", Vector3(10, 1, 0))
	var weapon: Node3D = player.get_current_weapon()
	_check(player._fire_weapon(weapon), "A real pistol shot succeeds")
	var state = player.get("_shot_recoil")
	var pending: Vector3 = state.remaining
	var barrel: Vector3 = -weapon.get_node("Muzzle").global_basis.z
	barrel.y = 0.0
	_check(pending.normalized().dot(barrel.normalized()) < -0.999, "Recoil uses actual aimed barrel direction")
	_check(not player._fire_weapon(weapon) and state.remaining == pending, "Cooldown cannot add recoil")
	weapon.set("_cooldown_remaining", 0.0)
	weapon.set("_magazine_ammo", 0)
	_check(not player._fire_weapon(weapon) and state.remaining == pending, "Dry fire cannot add recoil")
	_check(not player._fire_weapon(player.weapons[7]) and state.remaining == pending, "Minigun spin-up cannot add recoil")
	state.remaining = Vector3.ZERO
	state.shot("SHOTGUN", Vector3.FORWARD)
	var start: Vector3 = player.position
	for i in 30:
		player._update_move(1.0 / 60.0)
	_check(absf(player.position.z - start.z - 0.02) < 0.0001, "Real character moves backwards by the chosen amount")
	player.velocity = Vector3.FORWARD * 2.0
	player.ground_deceleration = 0.0
	start = player.position
	player._update_move(1.0 / 60.0)
	var control_motion: float = player.position.z - start.z
	player.position = start
	state.shot("SHOTGUN", Vector3.FORWARD)
	player._update_move(1.0 / 60.0)
	var walking_kick: float = player.position.z - start.z - control_motion
	_check(walking_kick > 0.005 and walking_kick < 0.02, "Recoil remains present while walking forward")
	_check(is_equal_approx(player.velocity.z, -2.0), "Recoil does not contaminate locomotion velocity")
	player.velocity = Vector3.ZERO
	state.remaining = Vector3.ZERO
	# A wall just behind the player's capsule must consume, not defer, recoil.
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.2)
	collision.shape = box
	wall.add_child(collision)
	stage.add_child(wall)
	wall.position = player.position + Vector3(0, 1, 0.47)
	await physics_frame
	await physics_frame
	start = player.position
	for i in 100:
		state.shot("SHOTGUN", Vector3.FORWARD)
	for i in 30:
		player._update_move(1.0 / 60.0)
	_check(player.position.z - start.z < 0.04 and state.remaining.is_zero_approx(), "Wall blocks recoil and no impulse builds up behind it")
	wall.queue_free()
	await physics_frame
	start = player.position
	player._update_move(0.1)
	_check(player.position.distance_to(start) < 0.0001, "Removing the wall releases no stored push")
	stage.queue_free()
	await process_frame
