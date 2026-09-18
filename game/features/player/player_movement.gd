extends CharacterBody3D

@export var move_speed: float = 6.0
@export var sprint_speed: float = 9.0
@export var ground_acceleration: float = 18.0
@export var sprint_acceleration: float = 22.0
@export var ground_deceleration: float = 13.0
@export var roll_speed: float = 13.0
@export var roll_duration: float = 0.24
@export var roll_cooldown: float = 0.65
@export var camera_rotation_speed: float = 95.0
@export var gravity_acceleration: float = 24.0
@export var max_health: float = 100.0
@export var walk_push_strength: float = 1.0
@export var sprint_push_strength: float = 3.2
@export var roll_push_strength: float = 4.5

@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var aim_pivot: Node3D = $AimPivot
@onready var weapon: Node3D = $AimPivot/PrototypeRifle
@onready var infection_runtime: Node = $InfectionRuntime

var health: float
var _roll_direction := Vector3.ZERO
var _roll_remaining: float = 0.0
var _roll_cooldown_remaining: float = 0.0


func _ready() -> void:
	health = max_health


func _physics_process(delta: float) -> void:
	_roll_cooldown_remaining = maxf(0.0, _roll_cooldown_remaining - delta)
	_update_camera_rotation(delta)
	_update_aim()
	_update_movement(delta)
	if Input.is_action_pressed("fire") and _roll_remaining <= 0.0:
		weapon.call("try_fire")


func take_damage(amount: float) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	health = maxf(0.0, health - amount)


func heal(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var previous := health
	health = minf(max_health, health + amount)
	return health - previous


func add_ammo_to_current_weapon(amount: int) -> int:
	if amount <= 0 or weapon == null or not weapon.has_method("add_reserve_ammo"):
		return 0
	return weapon.call("add_reserve_ammo", amount)


func absorb_mutagen(delta_seconds: float) -> float:
	return infection_runtime.call("absorb_mutagen", delta_seconds)


func get_mutation() -> float:
	return infection_runtime.call("get_mutation")


func _update_camera_rotation(delta: float) -> void:
	var rotation_input := Input.get_axis("camera_left", "camera_right")
	camera_rig.rotate_y(deg_to_rad(rotation_input * camera_rotation_speed * delta))


func _update_movement(delta: float) -> void:
	var direction := _read_move_direction()

	if _roll_remaining > 0.0:
		_roll_remaining = maxf(0.0, _roll_remaining - delta)
		velocity.x = _roll_direction.x * roll_speed
		velocity.z = _roll_direction.z * roll_speed
	elif Input.is_action_just_pressed("roll") and direction.length_squared() > 0.0001 and _roll_cooldown_remaining <= 0.0:
		_start_roll(direction)
	else:
		_apply_weighted_walk(direction, delta)

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity_acceleration * delta

	move_and_slide()
	_apply_enemy_collision_push()


func _apply_weighted_walk(direction: Vector3, delta: float) -> void:
	var sprinting := Input.is_action_pressed("sprint")
	var target_speed := sprint_speed if sprinting else move_speed
	var target := direction * target_speed
	var acceleration := sprint_acceleration if sprinting else ground_acceleration
	if direction.length_squared() <= 0.0001:
		acceleration = ground_deceleration

	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)


func _apply_enemy_collision_push() -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.25:
		return

	var strength := walk_push_strength
	if _roll_remaining > 0.0:
		strength = roll_push_strength
	elif Input.is_action_pressed("sprint"):
		strength = sprint_push_strength

	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		var collider := collision.get_collider() as Node3D
		if collider == null or not collider.has_method("apply_player_push"):
			continue
		var push_direction: Vector3 = collider.global_position - global_position
		push_direction.y = 0.0
		if push_direction.length_squared() <= 0.0001:
			continue
		collider.call("apply_player_push", push_direction.normalized(), strength)
		velocity.x *= 0.88
		velocity.z *= 0.88


func _read_move_direction() -> Vector3:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := camera.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var direction := right * input_vector.x + forward * -input_vector.y
	return direction.normalized() if direction.length_squared() > 1.0 else direction


func _start_roll(direction: Vector3) -> void:
	_roll_direction = direction.normalized()
	_roll_remaining = roll_duration
	_roll_cooldown_remaining = roll_cooldown
	velocity.x = _roll_direction.x * roll_speed
	velocity.z = _roll_direction.z * roll_speed


func _update_aim() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var mouse_delta := get_viewport().get_mouse_position() - viewport_size * 0.5
	if mouse_delta.length_squared() <= 4.0:
		return

	var screen_right := camera.global_transform.basis.x
	screen_right.y = 0.0
	screen_right = screen_right.normalized()
	var screen_forward := -camera.global_transform.basis.z
	screen_forward.y = 0.0
	screen_forward = screen_forward.normalized()
	var aim_direction := screen_right * mouse_delta.x + screen_forward * -mouse_delta.y
	if aim_direction.length_squared() <= 0.0001:
		return

	aim_pivot.look_at(aim_pivot.global_position + aim_direction.normalized(), Vector3.UP)
