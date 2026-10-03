extends "res://game/features/combat/prototype_rifle.gd"

const PROJECTILE := preload("res://game/features/combat/grenade_projectile.gd")
const ART := preload("res://game/features/combat/public/launcher_visual.gd")

func try_fire_at(target_point: Vector3) -> bool:
	if _cooldown_remaining > 0.0 or _reloading or not is_instance_valid(effects_root):
		return false
	if _magazine_ammo <= 0:
		_dry_fire()
		return false
	var projectile := PROJECTILE.new()
	projectile.configure_world(effects_root, impact_pool)
	effects_root.add_child(projectile)
	projectile.global_position = muzzle.global_position
	projectile.setup(target_point, get_parent().get_parent() as CollisionObject3D)
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
			pool.call("spawn_casing", casings, point, casing_radius, get_parent().get_parent() as CollisionObject3D, sound_event(2) if index < 3 else &"")
	super.start_reload()
