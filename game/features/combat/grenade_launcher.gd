extends "res://game/features/combat/prototype_rifle.gd"

const PROJECTILE := preload("res://game/features/combat/grenade_projectile.gd")
const ART := preload("res://game/features/combat/public/launcher_visual.gd")

@export_enum("Explosion 1:1", "Explosion 2:2") var explosion_variant := 2
var _test_controls_hovered := false


func get_explosion_variant() -> int:
	return explosion_variant


func toggle_explosion_variant() -> void:
	explosion_variant = 2 if explosion_variant == 1 else 1


func set_test_controls_hovered(hovered: bool) -> void:
	_test_controls_hovered = hovered


func try_fire_at(target_point: Vector3) -> bool:
	if _test_controls_hovered or _cooldown_remaining > 0.0 or _reloading or _magazine_ammo <= 0:
		return false
	var projectile := PROJECTILE.new()
	projectile.set_meta("grenade_explosion_variant", explosion_variant)
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = muzzle.global_position
	projectile.setup(target_point, get_parent().get_parent() as CollisionObject3D)
	_magazine_ammo -= 1
	_show_muzzle_flash()
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
			pool.call("spawn_casing", casings, point, casing_radius, get_parent().get_parent() as CollisionObject3D)
	super.start_reload()
