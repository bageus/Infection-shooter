extends CharacterBody3D

@export var max_health: float = 50.0
@export var move_speed: float = 4.5
@export var attack_range: float = 1.2
@export var attack_damage: float = 15.0
@export var attack_interval: float = 1.0
@export var gravity_acceleration: float = 24.0
@export var push_decay: float = 10.0
@export var max_push_speed: float = 6.0

@onready var body_mesh: MeshInstance3D = $Body
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var death_cloud: Area3D = $DeathCloud

var health: float
var _target: Node3D
var _attack_cooldown: float = 0.0
var _dead: bool = false
var _push_velocity := Vector3.ZERO


func _ready() -> void:
	health = max_health
	death_cloud.depleted.connect(_on_death_cloud_depleted)


func set_target(target: Node3D) -> void:
	_target = target


func apply_player_push(direction: Vector3, strength: float) -> void:
	if _dead or strength <= 0.0:
		return
	_push_velocity += direction.normalized() * strength
	if _push_velocity.length() > max_push_speed:
		_push_velocity = _push_velocity.normalized() * max_push_speed


func take_damage(amount: float) -> void:
	if amount <= 0.0 or _dead:
		return
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		_die()


func _physics_process(delta: float) -> void:
	if _dead:
		velocity = Vector3.ZERO
		return

	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	var desired := Vector3.ZERO

	if _target != null and is_instance_valid(_target):
		var offset := _target.global_position - global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance > attack_range:
			var direction := offset.normalized()
			desired = direction * move_speed
			if direction.length_squared() > 0.0001:
				look_at(global_position + direction, Vector3.UP)
		else:
			desired = Vector3.ZERO
		else:
			_try_attack()

	velocity.x = desired.x + _push_velocity.x
	velocity.z = desired.z + _push_velocity.z
	_push_velocity = _push_velocity.move_toward(Vector3.ZERO, push_decay * delta)

	_apply_gravity(delta)
	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity_acceleration * delta


func _try_attack() -> void:
	if _attack_cooldown > 0.0:
		return
	if _target != null and _target.has_method("take_damage"):
		_target.call("take_damage", attack_damage)
	_attack_cooldown = attack_interval


func _die() -> void:
	_dead = true
	collision_layer = 0
	collision_mask = 0
	collision_shape.disabled = true
	body_mesh.visible = false
	death_cloud.call("activate")


func _on_death_cloud_depleted() -> void:
	queue_free()
