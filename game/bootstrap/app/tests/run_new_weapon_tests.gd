extends SceneTree

const PLAYER := preload("res://game/features/player/public/player.tscn")
const LAYOUT := preload("res://game/bootstrap/app/mission_layout.gd")
const CROSSHAIR := preload("res://game/presentation/prototype_hud/public/crosshair.tscn")
var failures := 0
var _dropped: Array[int] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _drop(index: int, _point: Vector3) -> bool:
	_dropped.append(index)
	return true

func _run() -> void:
	var actor := PLAYER.instantiate() as CharacterBody3D
	actor.set_physics_process(false)
	root.add_child(actor)
	var effects := Node3D.new()
	root.add_child(effects)
	actor.call("configure_world", effects, null)
	actor.call("configure_weapon_drop", _drop)
	var crosshair := CROSSHAIR.instantiate()
	root.add_child(crosshair)
	crosshair.call("configure", actor)
	await process_frame
	await process_frame
	_check(actor.get("weapons").size() == 8, "Eight stable weapon definitions are wired")
	_test_pickup_models()
	await _test_rifles(actor, effects, crosshair)
	await _test_minigun(actor, effects, crosshair)
	crosshair.queue_free()
	actor.queue_free()
	effects.queue_free()
	await process_frame
	await create_timer(1.1).timeout
	print("New weapon tests: %d failures" % failures)
	quit(1 if failures else 0)

func _test_rifles(actor: CharacterBody3D, effects: Node3D, crosshair: Node) -> void:
	var guns: Array = actor.get("weapons")
	_check(guns[4].bullet_damage > guns[5].bullet_damage and guns[5].bullet_damage > guns[1].bullet_damage, "AK > M4 > Uzi damage")
	_check(guns[5].spread_degrees < guns[4].spread_degrees and guns[4].spread_degrees < guns[1].spread_degrees, "M4 < AK < Uzi spread")
	_check(guns[5].magazine_size > guns[4].magazine_size, "M4 has larger magazine than AK")
	for index in [4, 5, 6]:
		_check(actor.call("pickup_weapon", index), "New rifle replaces an owned slot")
		var gun: Node3D = actor.call("get_current_weapon")
		actor.set("_aim_point", Vector3(0, .4, -30))
		await process_frame
		await process_frame
		_check(String(actor.get_node("AnimationDriver").animation_player.current_animation).contains("Launcher"), "Rifles reuse Launcher two-hand stance")
		_check(gun.casing_scene.resource_path.ends_with("12_rifle_casing.glb"), "Rifle casing model assigned")
		_check(is_equal_approx(gun.casing_size_multiplier, 1.15 if index == 6 else 1.0), "Only sniper has enlarged rifle casings")
		_check(is_equal_approx(gun.camera_distance_bonus, 8.0 if index == 6 else 3.0), "Sniper widens camera farther than assault rifles")
		actor.call("_update_camera", 2.0)
		_check(absf(actor.get("camera").position.length() - float(actor.get("_camera_distance")) - gun.camera_distance_bonus) < .01, "Equipping rifle applies actual camera distance")
		var grip := gun.find_child("Grip_R", true, false) as Node3D
		actor.get_node("WeaponMount").call("sync_weapon", gun)
		_check(grip.global_position.distance_to(gun.global_position) < .001, "New right grip aligns with the hand socket")
		var pose: Node = actor.get_node("WeaponMount").get("equipment_pose")
		_check(pose.hand_error < .025, "Support hand reaches the authored grip without bone stretching")
		var before: int = gun.call("get_magazine_ammo")
		_check(actor.call("_fire_weapon", gun), "New rifle emits a real projectile")
		_check(gun.call("get_magazine_ammo") == before - 1, "Shot consumes exactly one round")
		_check(not actor.call("_fire_weapon", gun), "Cooldown prevents duplicate shot")
		if index == 6:
			_check(not gun.call("wants_continuous_fire") and gun.magazine_size == 4, "Sniper is semi-auto with four-round magazine")
			_check(gun.call("sound_event", 0) == &"rifle_fire", "Sniper uses the recorded rifle report")
			_check(crosshair.scope.visible and not crosshair.crosshair.visible, "Selecting sniper swaps crosshair to scope")
			_check(crosshair.scope.view.world_3d == actor.get_world_3d(), "Scope renders the actual shared world")
			_check(crosshair.scope.camera.fov < actor.get("camera").fov, "Scope lens genuinely magnifies with narrower FOV")
			await _test_scope_pixels(effects, crosshair.scope)
			for shot in 3:
				gun.set("_cooldown_remaining", 0.0)
				_check(actor.call("_fire_weapon", gun), "Sniper can fire remaining magazine rounds")
			_check(gun.call("get_magazine_ammo") == 0, "Four sniper shots empty the magazine")
			gun.call("start_reload")
			gun.call("_process", 3.0)
			_check(gun.call("get_magazine_ammo") == 4 and gun.call("get_reserve_ammo") == 20, "Sniper reload transfers exactly four reserve rounds")
		else:
			_check(not crosshair.scope.visible, "Assault rifles use the standard crosshair")
		for bullet in effects.get_children():
			if bullet.get("_weapon_name") != null:
				_check(bullet.get("_weapon_name") == gun.weapon_name, "Projectile carries the actual weapon identity")
				bullet.queue_free()
		await process_frame

func _test_minigun(actor: CharacterBody3D, effects: Node3D, crosshair: Node) -> void:
	_check(actor.call("pickup_weapon", 7), "Minigun pickup equips complete kit")
	var gun: Node3D = actor.call("get_current_weapon")
	await process_frame
	await process_frame
	var pose: Node = actor.get_node("WeaponMount").get("equipment_pose")
	_check(pose.hand_error < .025, "Minigun support hand reaches the front grip")
	_check(pose.backpack.visible, "Backpack appears on the equipped player")
	_check(pose.backpack.get_parent() is BoneAttachment3D, "Backpack follows the spine")
	_check(not crosshair.scope.visible, "Switching to minigun disables scope render")
	_check(gun.call("get_magazine_ammo") == 400 and gun.call("get_reserve_ammo") == 0, "HUD exposes one 400-round belt")
	gun.call("start_reload")
	_check(not gun.call("is_reloading"), "Minigun never enters reload")
	_check(gun.casing_size_multiplier == 1.15 and gun.casing_scene.resource_path.ends_with("12_rifle_casing.glb"), "Minigun uses enlarged rifle casings")
	for shot in 400:
		gun.set("_cooldown_remaining", 0.0)
		_check(actor.call("_fire_weapon", gun), "Every minigun belt round fires")
		if shot == 0:
			gun.call("_process", .01)
			_check(not gun.get("_barrel_cluster").transform.basis.is_equal_approx(Basis.IDENTITY), "Minigun barrel cluster spins during fire")
		for bullet in effects.get_children():
			if bullet.get("_weapon_name") != null:
				bullet.queue_free()
		if shot % 20 == 0:
			await process_frame
	_check(gun.call("get_magazine_ammo") == 0 and gun.get("_reserve_ammo") == 0, "400 shots consume the entire direct reserve")
	gun.set("_cooldown_remaining", 0.0)
	_check(not actor.call("_fire_weapon", gun) and not gun.call("is_reloading"), "Empty belt cannot shoot or auto-reload")
	_check(gun.call("add_reserve_ammo", 999) == 400, "Ammo pickup is capped to the belt capacity")
	_check(actor.call("select_weapon_slot", 1), "Normal weapon switch remains usable")
	await process_frame
	await process_frame
	_check(not pose.backpack.visible, "Backpack is hidden when minigun is holstered")
	actor.call("_update_camera", 2.0)
	_check(absf(actor.get("camera").position.length() - float(actor.get("_camera_distance"))) < .01, "Switching to original weapon restores the base camera distance")


func _test_pickup_models() -> void:
	var layout := LAYOUT.new()
	root.add_child(layout)
	for index in [4, 5, 6, 7]:
		_check(layout.spawn_weapon(index, Vector3(index, 0, 0)), "Level can place each new weapon")
		var pickup := layout.get_child(layout.get_child_count() - 1)
		_check(pickup.find_child("WeaponRoot", true, false) != null, "Pickup contains the real gun geometry")
		_check(pickup.find_child("BackpackRoot", true, false) == null, "Backpack is never visible on the floor")
	layout.queue_free()


func _test_scope_pixels(effects: Node3D, scope: Control) -> void:
	if DisplayServer.get_name() == "headless":
		print("Scope pixel assertion deferred to native Compatibility/Forward+ CI")
		return
	var target := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 4.0
	var red := StandardMaterial3D.new()
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.albedo_color = Color(.95, .02, .01)
	box.material = red
	target.mesh = box
	effects.add_child(target)
	target.global_position = Vector3(0, .4, -30)
	var center := Color.BLACK
	# A newly registered mesh may need several rendered frames to compile its
	# pipeline. Require the actual target pixel within a bounded frame budget.
	for frame in 12:
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = scope.view.get_texture().get_image()
		center = image.get_pixel(image.get_width() / 2, image.get_height() / 2)
		if center.r > .6 and center.g < .2:
			break
	if not (center.r > .6 and center.g < .2):
		print("Scope probe camera=%s target=%s update=%s" % [scope.camera.global_transform, target.global_position, scope.view.render_target_update_mode])
		var directory := OS.get_environment("POSE_CAPTURE_DIR")
		if not directory.is_empty():
			DirAccess.make_dir_recursive_absolute(directory)
			scope.view.get_texture().get_image().save_png(directory.path_join("scope_target_" + RenderingServer.get_current_rendering_method() + ".png"))
	_check(scope.camera.is_current(), "Scope keeps its camera active after sharing the world")
	_check(center.r > .6 and center.g < .2, "Native scope actually renders the target under its reticle: %s" % center)
	target.queue_free()
