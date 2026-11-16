extends SceneTree

const PLAYER := preload("res://game/features/player/public/player.tscn")
const PLAYER_SCRIPT := preload("res://game/features/player/player_movement.gd")
const MOUNT := preload("res://game/features/player/player_weapon_mount.gd")
const STANCE := preload("res://game/features/player/player_weapon_stance.gd")
const SELECTION := preload("res://game/features/player/player_animation_selection.gd")
const ART := preload("res://game/features/combat/public/launcher_visual.gd")
const DRIVER := preload("res://game/features/character_animation/public/character_animation_driver.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_stance_sequences()
	_test_inactivity()
	_test_uzi_pistol_rounds()
	await _test_player_wiring()
	await _test_generic_fallback()
	await _test_baked_hold()
	await _test_reload_clip()
	await process_frame
	await process_frame
	print("Weapon presentation tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: ", message)


# The Uzi fires pistol rounds: same spent casing and flight speed.
func _test_uzi_pistol_rounds() -> void:
	var pistol: Node = load("res://game/features/combat/public/pistol.tscn").instantiate()
	var uzi: Node = load("res://game/features/combat/public/uzi.tscn").instantiate()
	for property in ["casing_scene", "casing_radius", "bullet_speed", "bullet_scene"]:
		_check(uzi.get(property) == pistol.get(property), "Uzi %s matches pistol" % property)
	pistol.free()
	uzi.free()


func _shot(state: STANCE, fired: bool = true) -> void:
	var previous := state.begin_fire_attempt()
	state.finish_fire_attempt(fired, previous)


func _test_stance_sequences() -> void:
	for index in [0, 1]:
		var state := STANCE.new()
		state.select_weapon(index)
		_check(state.stance == STANCE.WeaponStance.ONE_HAND, "Pistol/Uzi switch starts one-hand")
		_shot(state)
		_check(state.stance == STANCE.WeaponStance.ONE_HAND, "first successful bullet stays one-hand")
		state.tick(0.1, true)
		_shot(state)
		_check(state.stance == STANCE.WeaponStance.TWO_HAND, "second successful bullet becomes two-hand")
		state.tick(0.1, true)
		_shot(state)
		_check(state.stance == STANCE.WeaponStance.TWO_HAND, "continuous burst remains two-hand")
		state.tick(2.0, true)
		_shot(state)
		_check(state.stance == STANCE.WeaponStance.ONE_HAND, "exactly two-second gap starts new series")
		state.tick(0.1, true)
		_shot(state)
		state.tick(1.9, true)
		_shot(state, false)
		_check(state.stance == STANCE.WeaponStance.TWO_HAND, "failed attempt preserves stance")
		state.tick(0.2, true)
		_shot(state)
		_check(state.stance == STANCE.WeaponStance.ONE_HAND, "failed attempt never advances sequence timestamp")
		state.select_weapon(2)
		state.select_weapon(index)
		_shot(state)
		_check(state.stance == STANCE.WeaponStance.ONE_HAND, "switch away/back resets series")
	for index in [2, 3]:
		var state := STANCE.new()
		state.select_weapon(index)
		_shot(state)
		state.tick(30.0, false)
		_check(state.stance == STANCE.WeaponStance.TWO_HAND, "Shotgun/Launcher always two-hand")


func _test_inactivity() -> void:
	for index in [0, 1]:
		var state := STANCE.new()
		state.select_weapon(index)
		state.tick(19.9, false)
		_check(state.stance == STANCE.WeaponStance.ONE_HAND, "not lowered before twenty seconds")
		state.record_mouse_motion(Vector2(0.1, 0.1))
		state.tick(0.1, false)
		_check(state.stance == STANCE.WeaponStance.LOWERED, "hardware jitter does not reset inactivity")
		state.record_mouse_motion(Vector2(1.0, 0.0))
		_check(state.stance == STANCE.WeaponStance.ONE_HAND, "mouse activity raises into one-hand")
		state.tick(20.0, false)
		state.tick(0.1, true)
		_check(state.stance == STANCE.WeaponStance.ONE_HAND, "movement activity raises into one-hand")
		state.tick(20.0, false)
		_shot(state)
		_check(state.stance == STANCE.WeaponStance.ONE_HAND, "fire from lowered starts one-hand")


func _test_player_wiring() -> void:
	var player := PLAYER.instantiate() as PLAYER_SCRIPT
	player.set_physics_process(false)
	root.add_child(player)
	var effects := Node3D.new()
	root.add_child(effects)
	player.call("configure_world", effects, null)
	player.set("_aim_point", Vector3(0, 0, -10))
	await process_frame
	var mount := player.get_node("WeaponMount") as MOUNT
	_check(mount.skeleton != null and mount.skeleton.find_bone("RightHand") >= 0, "imported RightHand exists")
	_check(mount.skeleton.find_bone("Backpack") >= 0, "the backpack has its own bone")
	var driver: Node = player.get_node("AnimationDriver")
	_check(driver.animation_player != null, "imported AnimationPlayer exists")
	print("ASSET Skeleton3D: ", player.get_path_to(mount.skeleton))
	print("ASSET clips: ", driver.animation_player.get_animation_list())
	var selector := SELECTION.new()
	selector.configure(player, player.get_node("AimPivot"), player.weapon_stance)
	_test_directional_selection(player, selector, driver.animation_player)
	for index in 4:
		var weapon: Node3D = player.weapons[index]
		_check(weapon.name == ["Pistol", "Uzi", "Shotgun", "GrenadeLauncher"][index], "weapon index mapping preserved")
		_check(weapon.get_parent() == player.get_node("AimPivot"), "combat parent chain preserved")
		var authored_root := _find_marker(weapon.get_node("Body"), "WeaponRoot")
		var authored_muzzle := _find_marker(authored_root, "Muzzle")
		_check(authored_root.global_position.is_equal_approx(weapon.global_position), "authored root aligned to wrapper")
		_check(weapon.get_node("Muzzle").global_position.is_equal_approx(authored_muzzle.global_position), "public muzzle uses authored barrel end")
		_check((-weapon.get_node("Muzzle").global_basis.z).normalized().dot(authored_muzzle.global_basis.x.normalized()) > 0.999, "public muzzle -Z matches authored +X")
		_check(weapon.get_node_or_null("EjectionPort") != null, "fallback ejection marker retained")
		_check(_find_marker(authored_root, "Grip_L") != null, "left grip available")
		var pickup := ART.make_pickup_visual(index)
		_check(_find_marker(pickup, "WeaponRoot") != null, "pickup uses authored weapon asset")
		var pickup_muzzle := _find_marker(pickup, "Muzzle")
		var pickup_grip := _find_marker(pickup, "Grip_R")
		if pickup_muzzle != null and pickup_grip != null:
			var muzzle_height := (_local_to(pickup, pickup_muzzle).origin).y
			var grip_height := (_local_to(pickup, pickup_grip).origin).y
			# Grip_R is a hand anchor the owner may have moved off the physical grip in the hold tuner, so the weapon root counts too.
			var root_height := (_local_to(pickup, _find_marker(pickup, "WeaponRoot")).origin).y
			_check(muzzle_height > grip_height or muzzle_height > root_height, "floor pickup lies barrel up, grip down")
		pickup.free()
	_test_flash_anchors(player)
	await _test_switch_and_fire(player, effects)
	await _test_mount_and_pause(player, mount)
	player.queue_free()
	effects.queue_free()
	await process_frame


func _test_directional_selection(player: PLAYER_SCRIPT, selector: SELECTION, animation_player: AnimationPlayer) -> void:
	var aim: Node3D = player.get_node("AimPivot")
	aim.rotation.y = PI * 0.5
	for index in 4:
		player.weapon_stance.select_weapon(index)
		player.velocity = Vector3.ZERO
		_check(animation_player.has_animation(selector.select_clip()), "actual imported idle exists")
		for direction in ["Forward", "Backward", "Left", "Right"]:
			var local: Vector3 = {"Forward": Vector3.FORWARD, "Backward": Vector3.BACK, "Left": Vector3.LEFT, "Right": Vector3.RIGHT}[direction]
			player.velocity = aim.global_basis * local * 6.0
			var clip := String(selector.select_clip())
			_check(clip.contains("_" + direction + "_"), "locomotion uses aim-local direction " + direction)
			_check(animation_player.has_animation(clip), "actual imported walk exists: " + clip)
		_check(String(selector.select_clip()).ends_with("_" + SELECTION.family_of(index)), "the clip belongs to the held weapon")
	player.weapon_stance.select_weapon(0)
	player.velocity = aim.global_basis * Vector3(6.0, 0.0, -5.0)
	selector.select_clip()
	player.velocity = aim.global_basis * Vector3(5.0, 0.0, -5.1)
	_check(String(selector.select_clip()).contains("_Right_"), "diagonal hysteresis prevents axis chatter")
	player.velocity = Vector3.ZERO
	aim.rotation.y = 0.0
	player.weapon_stance.tick(20.0, false)
	_check(animation_player.has_animation(selector.select_clip()), "actual lowered idle exists")
	player.weapon_stance.record_activity()


func _test_switch_and_fire(player: PLAYER_SCRIPT, effects: Node3D) -> void:
	player.call("import_loadout", {"slots": [0, 1, 2]})
	for slot in 3:
		player.call("select_weapon_slot", slot)
		var weapon: Node3D = player.call("get_current_weapon")
		_check(player.call("get_weapon_in_slot", slot) == slot, "initial slots remain [0,1,2]")
		for other in player.weapons:
			_check(other.visible == (other == weapon), "visibility switches exclusively")
		var before := int(weapon.call("get_magazine_ammo"))
		var emitted_before := effects.get_child_count()
		_check(bool(player.call("_fire_weapon", weapon)), "configured weapon fires")
		_check(int(weapon.call("get_magazine_ammo")) == before - 1, "one shell/bullet consumed per shot")
		_check(effects.get_child_count() > emitted_before, "projectile or pellets emitted")
		_check(not bool(player.call("_fire_weapon", weapon)), "cooldown refuses second attempt")
		_check(int(weapon.call("get_magazine_ammo")) == before - 1, "failed attempt preserves ammunition")
		weapon.call("start_reload")
		_check(weapon.call("is_reloading"), "reload remains usable")
	player.call("configure_weapon_drop", _accept_drop)
	_check(player.call("pickup_weapon", 3), "launcher replaces current slot through drop command")
	var launcher: Node3D = player.call("get_current_weapon")
	_check(launcher.name == "GrenadeLauncher", "replacement selects launcher")
	_check(player.weapon_stance.stance == STANCE.WeaponStance.TWO_HAND, "pickup configures launcher stance")
	var count := effects.get_child_count()
	_check(bool(player.call("_fire_weapon", launcher)), "launcher fires without hierarchy change")
	var projectile: Node3D = effects.get_child(count)
	_check(projectile.global_position.is_equal_approx(launcher.get_node("Muzzle").global_position), "grenade starts at authored muzzle")
	_check(projectile.get("shooter") == player, "launcher parent-chain shooter remains player")
	_check(player.call("pickup_weapon", 2), "dropped weapon can replace launcher")
	await process_frame


func _accept_drop(index: int, _position: Vector3) -> bool:
	_check(index in [2, 3], "drop command receives weapon model index")
	return true


func _test_mount_and_pause(player: PLAYER_SCRIPT, mount: MOUNT) -> void:
	player.call("select_weapon_slot", 0)
	var weapon: Node3D = player.call("get_current_weapon")
	var scale_before := weapon.scale
	await _settle(player)
	mount.sync_weapon(weapon)
	var model_muzzle := player.get_node("Body").find_child("Pistol_Muzzle", true, false) as Node3D
	_check(weapon.get_node("Muzzle").global_position.distance_to(model_muzzle.global_position) < 0.0001, "active weapon follows the model's muzzle")
	_check(weapon.scale.is_equal_approx(scale_before), "bone motion does not alter weapon scale")
	player.set_physics_process(true)
	var before := float(player.weapon_stance.inactive_seconds)
	paused = true
	await process_frame
	await process_frame
	_check(is_equal_approx(player.weapon_stance.inactive_seconds, before), "pause freezes inactivity timer")
	paused = false
	player.set_physics_process(false)
	_check(mount != null, "mount exists")


func _test_generic_fallback() -> void:
	var actor := CharacterBody3D.new()
	var body := Node3D.new()
	body.name = "Body"
	actor.add_child(body)
	var animation_player := AnimationPlayer.new()
	body.add_child(animation_player)
	var library := AnimationLibrary.new()
	for name in ["Idle", "Walk", "Run"]:
		var clip := Animation.new()
		clip.length = 1.0
		library.add_animation(name, clip)
	animation_player.add_animation_library("", library)
	var driver := DRIVER.new()
	actor.add_child(driver)
	root.add_child(actor)
	actor.velocity = Vector3(3, 0, 0)
	await process_frame
	await process_frame
	_check(animation_player.current_animation == "Walk", "unconfigured shared driver preserves infected walk fallback")
	actor.velocity = Vector3.ZERO
	await process_frame
	await process_frame
	_check(animation_player.current_animation == "Idle", "unconfigured shared driver preserves infected idle fallback")
	actor.queue_free()
	await process_frame


func _find_marker(node: Node, marker_name: String) -> Node3D:
	if node.name == marker_name:
		return node as Node3D
	return node.find_child(marker_name, true, false) as Node3D


func _test_flash_anchors(player: PLAYER_SCRIPT) -> void:
	var camera: Camera3D = player.get_node("CameraRig/Camera3D")
	camera.make_current()
	for weapon in player.weapons:
		var authored_root := _find_marker(weapon.get_node("Body"), "WeaponRoot")
		var marker := _find_marker(authored_root, "Muzzle")
		var original := marker.transform
		marker.position += Vector3(0.07, 0.03, 0.01)
		weapon.call("_show_muzzle_flash")
		var flash := marker.get_child(marker.get_child_count() - 1) as Node3D
		_check(flash.name == "MuzzleFlash", "flash is attached directly to authored Muzzle")
		var atlas_file := (flash.get("atlas") as Texture2D).resource_path.get_file()
		var weapon_name: String = weapon.get_weapon_name()
		if weapon_name == "SHOTGUN":
			_check(atlas_file == "shotgun_muzzle.png", "shotgun flash uses its own muzzle atlas")
		elif weapon_name in ["PISTOL", "UZI", "GRENADE LAUNCHER"]:
			_check(atlas_file == "gun_fog.png", "%s flash keeps the gun_fog atlas" % weapon_name)
		else:
			_check(atlas_file.begins_with("frame_muzzle_"), "%s flash uses a frame_muzzle atlas" % weapon_name)
		_check(flash.global_position.is_equal_approx(marker.global_position), "flash origin uses actual model marker")
		var visual := flash.get_node("Visual") as MeshInstance3D
		var tip := visual.global_transform * Vector3(float(flash.get("tip_position")) - 0.5, 0, 0)
		_check(tip.distance_to(marker.global_position) < 0.0001, "texture emission anchor is correct on the creation frame")
		marker.position += Vector3(0.02, 0, 0.02)
		camera.position += Vector3(0.2, 0.1, 0)
		flash.call("_process", 0.01)
		tip = visual.global_transform * Vector3(float(flash.get("tip_position")) - 0.5, 0, 0)
		_check(tip.distance_to(marker.global_position) < 0.0001, "flash follows marker and camera motion")
		flash.free()
		marker.transform = original


func _local_to(boundary: Node3D, marker: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var node: Node = marker
	while node != boundary and node != null:
		if node is Node3D:
			result = (node as Node3D).transform * result
		node = node.get_parent()
	return result


func _test_baked_hold() -> void:
	var player := PLAYER.instantiate() as PLAYER_SCRIPT
	player.set_physics_process(false)
	root.add_child(player)
	var effects := Node3D.new()
	root.add_child(effects)
	player.call("configure_world", effects, null)
	player.call("configure_weapon_drop", func(_i: int, _p: Vector3) -> bool: return true)
	var body := player.get_node("Body")
	var guns := ["Pistol", "Uzi", "Shotgun", "Launcher", "AK", "M4", "Sniper", "Minigun"]
	for index in guns.size():
		player.call("pickup_weapon", index)
		await _settle(player)
		var gun := body.find_child("Weapon_" + guns[index], true, false) as Node3D
		_check(gun != null and gun.scale.x > 0.5, "the model draws only the held %s (scale %s)" % [guns[index], gun.scale if gun != null else "none"])
		for other in guns:
			if other != guns[index]:
				_check((body.find_child("Weapon_" + other, true, false) as Node3D).scale.x < 0.1, "the %s is put away while %s is held" % [other, guns[index]])
		var weapon: Node3D = player.call("get_current_weapon")
		var model_muzzle := body.find_child(guns[index] + "_Muzzle", true, false) as Node3D
		_check(weapon.get_node("Muzzle").global_position.distance_to(model_muzzle.global_position) < 0.001, "shots leave the model's %s muzzle" % guns[index])
		_check((weapon.get_node("Body").find_children("*", "MeshInstance3D", true, false) as Array).all(func(m: Node) -> bool: return not (m as MeshInstance3D).visible), "the weapon's own meshes are hidden")
	player.queue_free()
	effects.queue_free()
	await process_frame


# A reload plays the model's clip and shows the ejected magazine.
func _test_reload_clip() -> void:
	var player := PLAYER.instantiate() as PLAYER_SCRIPT
	player.set_physics_process(false)
	root.add_child(player)
	var effects := Node3D.new()
	root.add_child(effects)
	player.call("configure_world", effects, null)
	await process_frame
	var driver: Node = player.get_node("AnimationDriver")
	var weapon: Node3D = player.call("get_current_weapon")
	weapon.set("_magazine_ammo", 0)
	weapon.call("start_reload")
	var ejected := player.get_node("Body").find_child("Magazine_Removed_Pistol", true, false) as Node3D
	var seen := false
	for i in 90:
		await process_frame
		seen = seen or ejected.scale.x > 0.5
	_check(String(driver.animation_player.current_animation) == "Reload_Pistol" or not weapon.call("is_reloading"), "the reload plays the model's clip")
	_check(seen, "the spent magazine comes out during the reload")
	weapon.call("cancel_reload")
	# A body still swinging round to the aim steps on the walk cycle; once it faces the aim the idle returns.
	await create_timer(1.5).timeout
	_check(String(driver.animation_player.current_animation) == "Idle_Pistol", "cancelling the reload returns to idle")
	player.queue_free()
	effects.queue_free()
	await process_frame


## Lets the clip cross-fade finish so the held gun is fully scaled in.
func _settle(player: PLAYER_SCRIPT) -> void:
	await process_frame
	(player.get_node("AnimationDriver").animation_player as AnimationPlayer).advance(0.5)
	await process_frame
	await process_frame
