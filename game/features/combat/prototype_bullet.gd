extends Node3D

var _direction := Vector3.ZERO
var _shooter: CollisionObject3D
var _speed: float = 32.0
var _damage: float = 20.0
var _range: float = 30.0
var _travelled: float = 0.0
var _weapon_name: String = "PISTOL"


func setup_projectile(
	direction: Vector3,
	shooter: CollisionObject3D,
	damage: float,
	speed: float,
	max_range: float,
	weapon_name: String = "PISTOL"
) -> void:
	_direction = direction.normalized()
	_shooter = shooter
	_damage = damage
	_speed = speed
	_range = max_range
	_weapon_name = weapon_name


func _physics_process(delta: float) -> void:
	if _travelled >= _range:
		queue_free()
		return

	var step := minf(_speed * delta, _range - _travelled)
	var finish := global_position + _direction * step
	var excluded: Array[RID] = []
	if _shooter != null:
		excluded.append(_shooter.get_rid())

	var remaining_start := global_position
	var remaining_finish := finish
	for pass_index in 5:
		var query := PhysicsRayQueryParameters3D.create(remaining_start, remaining_finish, 3)
		query.exclude = excluded
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			global_position = finish
			_travelled += step
			return

		var position: Vector3 = hit.get("position")
		var normal: Vector3 = hit.get("normal")
		var collider: Object = hit.get("collider")
		var stops_bullet := _handle_hit(collider, position, normal)
		if stops_bullet:
			global_position = position
			queue_free()
			return

		if collider is CollisionObject3D:
			excluded.append((collider as CollisionObject3D).get_rid())
		remaining_start = position + _direction * 0.04

	global_position = finish
	_travelled += step


func _handle_hit(collider: Object, position: Vector3, normal: Vector3) -> bool:
	if collider == null:
		return true

	var falloff := clampf(1.0 - _travelled / maxf(_range, 0.01), 0.35, 1.0)
	var hit_damage := _damage * falloff

	if collider.has_method("take_projectile_hit"):
		return bool(collider.call(
			"take_projectile_hit",
			hit_damage,
			position,
			normal,
			_direction,
			_weapon_name
		))

	if collider.has_method("take_damage"):
		if collider.has_method("take_projectile_damage"):
			collider.call("take_projectile_damage", hit_damage, position, _direction, _weapon_name)
		else:
			collider.call("take_damage", hit_damage)
		return true

	var parent := (collider as Node).get_parent() if collider is Node else null
	if parent != null and parent.has_method("take_projectile_hit"):
		return bool(parent.call(
			"take_projectile_hit",
			hit_damage,
			position,
			normal,
			_direction,
			_weapon_name
		))

	return true
