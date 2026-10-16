extends SceneTree

const STATE := preload("res://game/features/player/shooting_camera_state.gd")
const PLAYER := preload("res://game/features/player/public/player.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_envelope()
	await _test_player()
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	print("Shooting camera tests: %d failures" % failures)
	quit(1 if failures else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", message)


func _test_envelope() -> void:
	var light := STATE.new()
	var heavy := STATE.new()
	light.shot("PISTOL")
	heavy.shot("SNIPER RIFLE")
	_check(is_equal_approx(light.offset, 0.005), "First light shot targets 0.5 percent")
	_check(heavy.offset > light.offset, "Powerful weapons have a larger first impulse")
	for weapon in STATE.IMPULSES:
		var state := STATE.new()
		var previous := 0.0
		for i in 100:
			state.shot(weapon)
			_check(state.offset >= previous and state.offset <= 0.03, "Repeated shots accumulate with a hard three percent cap")
			previous = state.offset
			state.tick(0.04)
		state.tick(0.25)
		_check(is_equal_approx(state.offset, 0.03), "Short gaps do not cause zoom pumping")
		state.tick(3.0)
		_check(is_zero_approx(state.offset), "Stopped firing returns exactly to baseline")
	var coarse := STATE.new()
	var fine := STATE.new()
	coarse.shot("SHOTGUN")
	fine.shot("SHOTGUN")
	coarse.tick(0.8)
	for i in 80:
		fine.tick(0.01)
	_check(is_equal_approx(coarse.offset, fine.offset), "Hold expiry and recovery are independent of frame rate")


func _test_player() -> void:
	var player = PLAYER.instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	var effects := Node3D.new()
	root.add_child(effects)
	player.configure_world(effects, null)
	player.set("_aim_point", Vector3(0, 1, -10))
	var weapon: Node3D = player.get_current_weapon()
	_check(player._fire_weapon(weapon), "A real shot succeeds")
	var state = player.get("_shooting_camera")
	var offset: float = state.offset
	_check(offset > 0.0, "Successful shot drives camera envelope")
	_check(not player._fire_weapon(weapon) and state.offset == offset, "Cooldown refusal cannot add camera recoil")
	weapon.set("_cooldown_remaining", 0.0)
	weapon.set("_magazine_ammo", 0)
	_check(not player._fire_weapon(weapon) and state.offset == offset, "Empty magazine cannot add camera recoil")
	var minigun: Node3D = player.weapons[7]
	_check(not player._fire_weapon(minigun) and state.offset == offset, "Spin-up cannot add camera recoil")
	for distance in [9.0, 24.0]:
		for index in [0, 4, 6, 7]:
			player.set("current_weapon_index", 0)
			player.get("_slot_weapons")[0] = index
			player.set("_camera_distance", distance)
			var bonus: float = player.get_current_weapon().get("camera_distance_bonus")
			var baseline: float = distance + bonus
			player.camera.position = player.camera.position.normalized() * baseline
			for i in 20:
				state.shot("SNIPER RIFLE")
			for i in 60:
				state.shot("PISTOL")
				player._update_camera(1.0 / 60.0)
				_check(player.camera.position.length() <= baseline * 1.03 + 0.00001, "Camera stays inside 3 percent of manual zoom plus weapon bonus")
			_check(player.camera.position.length() > baseline * 1.029, "Smoothed camera reaches the readable maximum")
			for i in 360:
				player._update_camera(1.0 / 60.0)
			_check(absf(player.camera.position.length() - baseline) < 0.002, "Camera recovers while preserving selected weapon bonus")
	player.queue_free()
	effects.queue_free()
	await process_frame
