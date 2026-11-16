extends SceneTree
## Regressions of the baked hero: it stands on the floor, the roll stays in place, the cycles are paced for the ground speed,
## the flashlight rides under the held gun, and aiming keeps the muzzle on the drawn barrel.
const PLAYER := preload("res://game/features/player/public/player.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var player := PLAYER.instantiate() as CharacterBody3D
	player.set_physics_process(false)
	root.add_child(player)
	var effects := Node3D.new()
	root.add_child(effects)
	player.call("configure_world", effects, null)
	player.call("configure_weapon_drop", func(_i: int, _p: Vector3) -> bool: return true)
	for i in 6:
		await process_frame
	var body := player.get_node("Body") as Node3D
	var capsule := (player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	_check(is_equal_approx(body.global_position.y, player.global_position.y - capsule.height * 0.5), "The model's feet are at the bottom of the capsule, not floating")
	var driver: Node = player.get_node("AnimationDriver")
	var clips := driver.get("animation_player") as AnimationPlayer
	var roll := clips.get_animation(driver.get("dodge_clip"))
	var travelled := 0.0
	for track in roll.get_track_count():
		if roll.track_get_type(track) == Animation.TYPE_POSITION_3D and str(roll.track_get_path(track)).ends_with(":Root"):
			for key in roll.track_get_key_count(track):
				travelled = maxf(travelled, (roll.track_get_key_value(track, key) as Vector3).length())
	_check(travelled == 0.0, "The roll clip does not carry the model away from the hero (%s m)" % travelled)
	_check(clips.get_animation("Run_Forward_Pistol").get_meta("ref_speed", 0.0) > 3.0 and clips.get_animation("Walk_Forward_Pistol").get_meta("ref_speed", 0.0) > 0.0, "Walk and run cycles name their ground speed")
	player.velocity = Vector3(0, 0, -float(player.get("move_speed")))
	driver.call("_process_skeletal", float(player.get("move_speed")))
	_check(clips.current_animation.begins_with("Run_"), "Normal movement speed plays the run cycle (%s)" % clips.current_animation)
	_check(clips.speed_scale > 1.0 and clips.speed_scale < 2.0, "The run cycle is sped up to the ground speed (x%.2f)" % clips.speed_scale)
	(player.get_node("AimPivot") as Node3D).global_rotation = Vector3.ZERO
	player.velocity = Vector3(1.0, 0.0, -1.0).normalized() * float(player.get("move_speed"))
	var diagonal_clip: StringName = (player.get("_animation_selection") as RefCounted).call("select_clip")
	var diagonal := body.find_child("DiagonalLegs", true, false)
	_check(diagonal != null and String(diagonal.get("clip")).begins_with("Run_") and String(diagonal.get("clip")) != String(diagonal_clip) and absf(float(diagonal.get("weight")) - 0.5) < 0.05, "A diagonal run blends the legs half way toward the other axis (%s + %s)" % [diagonal_clip, diagonal.get("clip") if diagonal != null else "none"])
	var light := player.find_child("Flashlight", true, false) as SpotLight3D
	var muzzle := body.find_child("Pistol_Muzzle", true, false) as Node3D
	_check(light != null and light.find_parent("Pistol_Muzzle") == muzzle, "The flashlight rides on the held gun's muzzle")
	_check_lens_glow(light)
	var weapon: Node3D = player.call("get_current_weapon")
	var mount := player.get_node("WeaponMount")
	mount.call("sync_weapon", weapon)
	var before: Vector3 = (weapon.get_node("Muzzle") as Node3D).global_position
	weapon.call("aim_at", before + Vector3(4, 1, -3))
	var shot_muzzle := weapon.get_node("Muzzle") as Node3D
	_check(shot_muzzle.global_position.distance_to(before) < 0.001, "Aiming keeps the muzzle where the drawn barrel ends")
	_check((-shot_muzzle.global_basis.z).dot((Vector3(4, 1, -3)).normalized()) > 0.999, "The shot leaves the muzzle straight for the target")
	var selection: RefCounted = player.get("_animation_selection")
	player.velocity = Vector3.ZERO
	(player.get_node("AimPivot") as Node3D).global_rotation = Vector3(0.0, 1.5, 0.0)
	body.global_rotation = Vector3(0.0, PI, 0.0)
	_check(selection.call("select_clip") == &"Walk_Forward_Pistol" and float(driver.get("turn_step_speed")) > 0.0, "Turning on the spot steps the feet round on the walk cycle")
	body.global_rotation = Vector3(0.0, 1.5 + PI, 0.0)
	selection.set("_turn_until", 0.0)
	_check(selection.call("select_clip") == &"Idle_Pistol" and float(driver.get("turn_step_speed")) == 0.0, "Facing the aim again returns to idle")
	var events: Dictionary = preload("res://game/core/audio/public/sound_events.gd").EVENTS
	_check(float(events[&"step_concrete"][1]) - float(events[&"backpack_rattle"][1]) >= 8.0, "The backpack rattle sits well below the footstep")
	var drop := preload("res://game/features/player/magazine_drop_variety.gd")
	var reload := clips.get_animation("Reload_Pistol")
	var track := -1
	for index in reload.get_track_count():
		if reload.track_get_type(index) == Animation.TYPE_POSITION_3D and str(reload.track_get_path(index)).ends_with("Magazine_Removed_Pistol"):
			track = index
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	drop.vary(reload, rng)
	var first := reload.track_get_key_value(track, reload.track_get_key_count(track) - 1) as Vector3
	var start := reload.track_get_key_value(track, 0) as Vector3
	rng.seed = 2
	drop.vary(reload, rng)
	var second := reload.track_get_key_value(track, reload.track_get_key_count(track) - 1) as Vector3
	_check(first.distance_to(second) > 0.05 and is_equal_approx(first.y, second.y), "Two reloads drop the magazine to different spots on the floor")
	_check((reload.track_get_key_value(track, 0) as Vector3).is_equal_approx(start), "The magazine still leaves the gun from the same place")
	var slid := 0.0
	for key in reload.track_get_key_count(track):
		if reload.track_get_key_time(track, key) >= drop.land_time(reload):
			slid = maxf(slid, (reload.track_get_key_value(track, key) as Vector3).distance_to(drop.rest(reload).origin))
	_check(drop.land_time(reload) > 0.0 and slid < 0.001, "The landed magazine stays where it fell, it does not slide (%.3f m)" % slid)
	await _check_aim_and_lean(player, body)
	var standing_y := body.position.y
	var seconds: float = player.call("play_death_fall")
	_check(seconds > 0.8 and float(player.call("play_death_fall")) == 0.0, "Death starts one fall that takes about a second (%s s)" % seconds)
	await create_timer(seconds).timeout
	_check(absf(body.global_basis.y.y) < 0.05 and body.position.y > standing_y, "The dead hero lies on the floor, lifted by the body's thickness")
	print("Hero model regression tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)


## The drawn gun meets the aim for every hold, the minigun's barrels keep their axis, and running leans the body.
func _check_aim_and_lean(player: CharacterBody3D, body: Node3D) -> void:
	player.set("input_locked", true)
	var body_aim := preload("res://game/features/player/player_body_aim.gd")
	var aim_direction := Vector3(0.3, 0.0, -1.0).normalized()
	var mount_node := player.get_node("WeaponMount")
	(player.get_node("AimPivot") as Node3D).global_rotation = Vector3(0.0, atan2(-aim_direction.x, -aim_direction.z), 0.0)
	for slot in [4, 5, 2, 7]:
		player.call("pickup_weapon", slot)
		var settled := Time.get_ticks_msec() + 1800
		while Time.get_ticks_msec() < settled:
			body_aim.turn_body(body, aim_direction, 1.0 / 60.0, mount_node.call("barrel_yaw_offset"))
			await process_frame
		var held := mount_node.get("_model_muzzle") as Node3D
		var drawn: Vector3 = -(held.global_basis.orthonormalized() * Basis(Vector3.UP, -PI * 0.5)).z
		var miss := rad_to_deg(absf(angle_difference(atan2(drawn.x, drawn.z), atan2(aim_direction.x, aim_direction.z))))
		_check(miss < 1.5, "The drawn %s points at the aim (off by %.1f degrees)" % [player.call("get_current_weapon").call("get_weapon_name"), miss])
	var barrels := mount_node.get("_model_barrels") as MeshInstance3D
	var centre: Vector3 = barrels.get_aabb().get_center()
	var spun := Basis(Vector3.RIGHT, 1.1)
	barrels.transform = Transform3D(spun, centre - spun * centre)
	_check((barrels.transform * centre).is_equal_approx(centre), "The minigun's barrels turn about their own axis")
	player.velocity = Vector3(0.0, 0.0, -8.1)
	for i in 120:
		body_aim.turn_body(body, Vector3(0, 0, -1), 1.0 / 60.0)
	_check(body.global_basis.y.dot(Vector3(0, 0, -1)) > 0.08, "Running forward leans the body into the run (%.2f)" % body.global_basis.y.z)
	player.velocity = Vector3.ZERO
	for i in 120:
		body_aim.turn_body(body, Vector3(0, 0, -1), 1.0 / 60.0)
	_check(absf(body.global_basis.y.z) < 0.01, "Standing straightens the body again")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _check_lens_glow(light: SpotLight3D) -> void:
	var rig := root.find_child("FlashlightRig", true, false)
	var glow := light.get_node("LensGlow") as MeshInstance3D
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	light.visible = true
	light.light_energy = float(rig.get("ENERGY"))
	camera.global_position = light.global_position - light.global_basis.z * 3.0
	rig.call("_update_glow")
	var facing := (glow.material_override as StandardMaterial3D).albedo_color.a
	camera.global_position = light.global_position + light.global_basis.z * 3.0
	rig.call("_update_glow")
	_check(facing > 0.9 * float(rig.get("GLOW_STRENGTH")) and not glow.visible, "The lit lens glows toward a camera it faces, not from behind (%.2f)" % facing)
	camera.queue_free()
