extends Node3D

@export var speed: float = 32.0
@export var damage: float = 20.0
@export var lifetime: float = 1.5

var _direction := Vector3.ZERO
var _shooter: CollisionObject3D


func setup(direction: Vector3, shooter: CollisionObject3D) -> void:
	_direction = direction.normalized()
	_shooter = shooter


func _physics_process(delta: float) -> void:
	if _direction.length_squared() <= 0.0001:
		queue_free()
		return

	var start := global_position
	var finish := start + _direction * speed * delta
	var query := PhysicsRayQueryParameters3D.create(start, finish, 3)
	if _shooter != null:
		query.exclude = [_shooter.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit.get("position")
		var collider: Object = hit.get("collider")
		if collider != null and collider.has_method("take_damage"):
			collider.call("take_damage", damage)
		queue_free()
		return

	global_position = finish
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
