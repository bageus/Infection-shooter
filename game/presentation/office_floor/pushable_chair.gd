extends AnimatableBody3D

@export var push_impulse := 2.4
@export var max_horizontal_speed := 4.5
@export var max_health := 45.0
var _health := 45.0

func _ready() -> void:
	_health = max_health
	add_to_group("pushable_chair")

func push_from_character(character_position: Vector3, movement: Vector3) -> void:
	var direction := global_position - character_position
	direction.y = 0.0
	if movement.length_squared() > 0.01:
		direction = (direction.normalized() * 0.45 + movement.normalized() * 0.55).normalized()
	elif direction.length_squared() > 0.001:
		direction = direction.normalized()
	else:
		direction = Vector3.FORWARD
	var distance := push_impulse * 0.06
	var motion := direction * distance
	move_and_collide(motion)

func _physics_process(_delta: float) -> void:
	pass

func take_projectile_hit(damage: float, _hit_position: Vector3, _hit_normal: Vector3, direction: Vector3, weapon_name: String) -> bool:
	var multiplier := 1.35 if weapon_name == "SHOTGUN" else 1.0
	_health -= maxf(damage, 0.0) * multiplier
	var impulse_direction := direction
	impulse_direction.y = 0.0
	if impulse_direction.length_squared() > 0.001:
		move_and_collide(impulse_direction.normalized() * 0.12)
	if _health <= 0.0:
		queue_free()
	return true

func take_melee_hit(damage: float, _hit_position: Vector3, direction: Vector3) -> void:
	_health -= maxf(damage, 0.0)
	var impulse_direction := direction
	impulse_direction.y = 0.0
	if impulse_direction.length_squared() > 0.001:
		move_and_collide(impulse_direction.normalized() * 0.16)
	if _health <= 0.0:
		queue_free()
