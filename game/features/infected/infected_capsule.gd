extends CharacterBody3D

@export var max_health: float = 50.0
@export var move_speed: float = 4.5
@export var attack_range: float = 1.2
@export var attack_damage: float = 15.0
@export var attack_interval: float = 1.0
@export var gravity_acceleration: float = 24.0

@onready var body_mesh: MeshInstance3D = $Body
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var death_cloud: Area3D = $DeathCloud

var health: float
var _target: Node3D
var _attack_cooldown: float = 0.0
var _dead: bool = false


func _ready() -> void:
	health = max_health
	death_cloud.depleted.connect(_on_death_cloud_depleted)


func set_target(target: Node3D) -> void:
	_target = target


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
	if _target == null or not is_instance_valid(_target):
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		return

	var offset := _target.global_position - global_position
	offset.y = 0.0
	var distance := offset.length()

	if distance > attack_range:
		var direction := offset.normalized()
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
		if direction.length_squared() > 0.0001:
			look_at(global_position + direction, Vector3.UP)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_try_attack()

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
