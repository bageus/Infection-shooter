extends Node3D
var _direction := Vector3.ZERO
var _shooter: CollisionObject3D
var _speed: float = 32.0
var _damage: float = 20.0
var _range: float = 30.0
var _travelled: float = 0.0
func setup_projectile(direction: Vector3, shooter: CollisionObject3D, damage: float, speed: float, max_range: float) -> void:
	_direction = direction.normalized()
	_shooter = shooter
	_damage = damage
	_speed = speed
	_range = max_range
func _physics_process(delta: float) -> void:
	if _travelled >= _range:
		queue_free()
		return
	var step := minf(_speed * delta, _range - _travelled)
	var finish := global_position + _direction * step
	var query := PhysicsRayQueryParameters3D.create(global_position, finish, 3)
	if _shooter != null: query.exclude = [_shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit.get("position")
		var collider: Object = hit.get("collider")
		if collider != null and collider.has_method("take_damage"):
			var falloff := clampf(1.0 - _travelled / maxf(_range, 0.01), 0.35, 1.0)
			collider.call("take_damage", _damage * falloff)
		queue_free()
		return
	global_position = finish
	_travelled += step
