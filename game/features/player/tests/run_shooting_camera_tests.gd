extends SceneTree

const STATE := preload("res://game/features/player/shooting_camera_state.gd")
const PLAYER := preload("res://game/features/player/public/player.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_envelope()
	await _test_player()
	await _test_adjustment()
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
	_check(is_equal_approx(light.offset, 0.01), "First light shot targets 1 percent")
	_check(heavy.offset > light.offset, "Powerful weapons have a larger first impulse")
	for weapon in STATE.IMPULSES:
		var state := STATE.new()
		var previous := 0.0
		for i in 100:
			state.shot(weapon)
			_check(state.offset >= previous and state.offset <= STATE.MAX_OFFSET, "Repeated shots accumulate with a hard six percent cap")
			previous = state.offset
			state.tick(0.04)
		_check(is_equal_approx(state.offset, STATE.MAX_OFFSET), "Sustained fire reaches the cap without recovering in between")
		state.tick(3.0)
		_check(is_zero_approx(state.offset), "Stopped firing returns exactly to baseline")
	var quick := STATE.new()
	quick.shot("SNIPER RIFLE")
	quick.tick(0.3)
	_check(quick.offset < 0.01, "A single sniper pull-back snaps back within a third of a second")
	var coarse := STATE.new()
	var fine := STATE.new()
	coarse.shot("SHOTGUN")
	fine.shot("SHOTGUN")
	coarse.tick(0.1)
	for i in 10:
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
				_check(player.camera.position.length() <= baseline * (1.0 + STATE.MAX_OFFSET) + 0.00001, "Camera stays inside the shot cap of manual zoom plus weapon bonus")
			_check(player.camera.position.length() > baseline * (1.0 + STATE.MAX_OFFSET - 0.001), "Smoothed camera reaches the readable maximum")
			for i in 360:
				player._update_camera(1.0 / 60.0)
			_check(absf(player.camera.position.length() - baseline) < 0.002, "Camera recovers while preserving selected weapon bonus")
	player.queue_free()
	effects.queue_free()
	await process_frame


func _test_adjustment() -> void:
	var player = PLAYER.instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	player.set_camera_adjustment({"yaw": 125.5, "pitch": -61.25, "distance": 15.0})
	var view: Dictionary = player.get_camera_adjustment()
	_check(absf(view.yaw - 125.5) < 0.001 and absf(view.pitch + 37.3) < 0.001, "Camera yaw round-trips in degrees and pitch stays fixed at -37.3")
	_check(is_equal_approx(view.distance, 15.0), "Manual distance round-trips")
	_check(player.camera.position.normalized().dot(player.camera.basis.z) > 0.9999, "Orbit keeps the player at its focus")
	player._update_camera(0.016)
	var updated: Dictionary = player.get_camera_adjustment()
	_check(absf(updated.yaw - view.yaw) < 0.001 and absf(updated.pitch - view.pitch) < 0.001, "Normal camera update preserves selected angles")
	view = updated
	player.set_camera_adjustment({"yaw": NAN, "pitch": -10.0, "distance": 20.0})
	_check(player.get_camera_adjustment() == view, "Non-finite preferences cannot alter camera")
	player.set_camera_adjustment({"yaw": 12.0})
	_check(player.get_camera_adjustment() == view, "Incomplete preferences preserve defaults")
	player.set_camera_adjustment({"yaw": 720.0, "pitch": 1000.0, "distance": 999.0})
	view = player.get_camera_adjustment()
	_check(is_zero_approx(view.yaw) and absf(view.pitch + 37.3) < 0.001 and view.distance == player.camera_max_distance, "Preferences clamp yaw and distance; pitch stays fixed")
	player.queue_free()
	await process_frame
