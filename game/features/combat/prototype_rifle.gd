extends Node3D

@export var damage: float = 20.0
@export var shots_per_second: float = 5.0
@export var max_range: float = 40.0

var _cooldown_remaining: float = 0.0


func _process(delta: float) -> void:
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)


func try_fire() -> bool:
	if _cooldown_remaining > 0.0:
		return false

	var from := global_position
	var direction := -global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * max_range, 2)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider: Object = hit.get("collider")
		if collider != null and collider.has_method("take_damage"):
			collider.call("take_damage", damage)

	_cooldown_remaining = 1.0 / maxf(shots_per_second, 0.01)
	return true
