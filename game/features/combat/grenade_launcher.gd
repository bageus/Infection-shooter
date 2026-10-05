extends "res://game/features/combat/prototype_rifle.gd"

const PROJECTILE := preload("res://game/features/combat/grenade_projectile.gd")
const ART := preload("res://game/features/combat/public/launcher_visual.gd")

func aim_at(target_point: Vector3) -> void:
	# Solve launch and muzzle position together; convergence is bounded.
	for iteration in 8:
		var velocity := PROJECTILE.launch_velocity(muzzle.global_position, target_point)
		if velocity.length_squared() < 0.000001:
			return
		var axis := -muzzle.global_basis.z.normalized()
		var turn := Basis(Quaternion(axis, velocity.normalized()))
		global_basis = turn * global_basis


func try_fire_at(target_point: Vector3) -> bool:
	if _cooldown_remaining > 0.0 or _reloading or not is_instance_valid(effects_root):
		return false
	if _magazine_ammo <= 0:
		_dry_fire()
		return false
	aim_at(target_point)
	var projectile := PROJECTILE.new()
	projectile.configure_world(effects_root, impact_pool)
	effects_root.add_child(projectile)
	projectile.global_position = muzzle.global_position
	projectile.collision_origin = AIM_GEOMETRY.collision_origin(self, muzzle)
	projectile.setup(target_point, get_parent().get_parent() as CollisionObject3D)
	var obstruction := BARREL_GUARD.obstruction(self, muzzle, get_parent().get_parent() as CollisionObject3D)
	if not obstruction.is_empty():
		projectile.set_physics_process(false)
		projectile.set("_exploded", true)
		projectile.call_deferred("_explode_at", obstruction["position"], obstruction["normal"], obstruction["collider"])
	_magazine_ammo -= 1
	_show_muzzle_flash()
	SFX.play(self, sound_event(0), muzzle.global_position)
	_cooldown_remaining = 1.0 / shots_per_second
	return true


func start_reload() -> void:
	if _reloading or _magazine_ammo >= magazine_size or _reserve_ammo <= 0:
		return
	var casings := ART.casing_model()
	var pool := get_parent().get_node_or_null("SpentCasings")
	if pool != null and casings != null:
		for index in 6:
			var point := ejection_port.global_transform
			point.origin += Vector3(randf_range(-0.08, 0.08), 0, randf_range(-0.07, 0.07))
			pool.call("spawn_casing", casings, point, casing_radius, get_parent().get_parent() as CollisionObject3D, sound_event(2) if index < 3 else &"", 0.7)
	super.start_reload()
