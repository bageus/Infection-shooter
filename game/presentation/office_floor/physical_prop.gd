extends RigidBody3D

@export var max_health := 70.0
@export var bullet_impulse := 1.8
@export var character_push_impulse := 2.8
@export var breakable := true
@export var max_linear_speed := 7.0
@export var max_angular_speed := 8.0

var _health := 70.0

func _ready() -> void:
	_health = max_health
	add_to_group("physical_props")
	contact_monitor = true
	max_contacts_reported = 8
	continuous_cd = true
	collision_layer = 1
	collision_mask = 3
	can_sleep = true

func push_from_character(character_position: Vector3, movement: Vector3) -> void:
	if movement.length_squared() < 0.01:
		return
	var direction := movement.normalized()
	var offset := global_position - character_position
	offset.y = 0.0
	if offset.length_squared() > 0.001:
		direction = (direction * 0.7 + offset.normalized() * 0.3).normalized()
	sleeping = false
	apply_central_impulse(direction * character_push_impulse)

func take_projectile_hit(damage: float, hit_position: Vector3, _hit_normal: Vector3, direction: Vector3, weapon_name: String) -> bool:
	var multiplier := 1.8 if weapon_name == "SHOTGUN" else (0.7 if weapon_name == "UZI" else 1.0)
	var impulse := bullet_impulse * multiplier
	sleeping = false
	apply_impulse(direction.normalized() * impulse, hit_position - global_position)
	_health -= maxf(damage, 0.0) * multiplier
	if breakable and _health <= 0.0:
		_break_physical_prop(hit_position, direction)
	return true

func take_melee_hit(damage: float, hit_position: Vector3, direction: Vector3) -> void:
	sleeping = false
	apply_impulse(direction.normalized() * character_push_impulse, hit_position - global_position)
	_health -= maxf(damage, 0.0)
	if breakable and _health <= 0.0:
		_break_physical_prop(hit_position, direction)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if state.linear_velocity.length() > max_linear_speed:
		state.linear_velocity = state.linear_velocity.normalized() * max_linear_speed
	if state.angular_velocity.length() > max_angular_speed:
		state.angular_velocity = state.angular_velocity.normalized() * max_angular_speed


func _break_physical_prop(hit_position: Vector3, direction: Vector3) -> void:
	if is_queued_for_deletion():
		return
	var root := get_parent()
	var visual := get_node_or_null("Visual")
	if visual == null and root != null:
		visual = root.get_node_or_null("Visual")
	if visual != null:
		for child in visual.get_children():
			if child is MeshInstance3D:
				var fragment := RigidBody3D.new()
				fragment.mass = 0.6
				fragment.collision_layer = 0
				fragment.collision_mask = 1
				get_tree().current_scene.add_child(fragment)
				fragment.global_position = (child as MeshInstance3D).global_position
				var copy := (child as MeshInstance3D).duplicate()
				fragment.add_child(copy)
				copy.transform = Transform3D.IDENTITY
				fragment.apply_central_impulse(direction.normalized() * randf_range(0.4, 1.4) + Vector3.UP * randf_range(0.2, 0.8))
	queue_free()
