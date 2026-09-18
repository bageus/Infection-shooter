extends CharacterBody3D

@export var move_speed: float = 6.0
@export var sprint_speed: float = 9.0
@export var roll_speed: float = 13.0
@export var roll_duration: float = 0.24
@export var roll_cooldown: float = 0.65
@export var gravity_acceleration: float = 24.0
@export var max_health: float = 100.0

@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var aim_pivot: Node3D = $AimPivot
@onready var weapon: Node3D = $AimPivot/PrototypeRifle
@onready var infection_runtime: Node = $InfectionRuntime

var health: float
var _last_move_direction := Vector3(0, 0, -1)
var _roll_direction := Vector3.ZERO
var _roll_remaining: float = 0.0
var _roll_cooldown_remaining: float = 0.0


func _ready() -> void:
	health = max_health


func _physics_process(delta: float) -> void:
	_roll_cooldown_remaining = maxf(0.0, _roll_cooldown_remaining - delta)
	_update_aim()
	_update_movement(delta)
	if Input.is_action_pressed("fire") and _roll_remaining <= 0.0:
		weapon.call("try_fire")


func take_damage(amount: float) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	health = maxf(0.0, health - amount)


func absorb_mutagen(delta_seconds: float) -> float:
	return infection_runtime.call("absorb_mutagen", delta_seconds)


func get_mutation() -> float:
	return infection_runtime.call("get_mutation")


func _update_movement(delta: float) -> void:
	var direction := _read_move_direction()
	if _roll_remaining > 0.0:
		_roll_remaining = maxf(0.0, _roll_remaining - delta)
		velocity.x = _roll_direction.x * roll_speed
		velocity.z = _roll_direction.z * roll_speed
	elif Input.is_action_just_pressed("roll") and _roll_cooldown_remaining <= 0.0:
		_start_roll(direction)
	else:
		var speed := sprint_speed if Input.is_action_pressed("sprint") else move_speed
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity_acceleration * delta
	move_and_slide()


func _read_move_direction() -> Vector3:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := camera.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var direction := right * input_vector.x + forward * -input_vector.y
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	if direction.length_squared() > 0.0001:
		_last_move_direction = direction.normalized()
	return direction


func _start_roll(direction: Vector3) -> void:
	_roll_direction = direction.normalized() if direction.length_squared() > 0.0001 else _last_move_direction
	_roll_remaining = roll_duration
	_roll_cooldown_remaining = roll_cooldown
	velocity.x = _roll_direction.x * roll_speed
	velocity.z = _roll_direction.z * roll_speed


func _update_aim() -> void:
	var mouse_position := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_direction := camera.project_ray_normal(mouse_position)
	var aim_plane := Plane(Vector3.UP, global_position.y)
	var distance = aim_plane.intersects_ray(ray_origin, ray_direction)
	if distance == null:
		return
	var target: Vector3 = ray_origin + ray_direction * distance
	var flat_target := Vector3(target.x, aim_pivot.global_position.y, target.z)
	if aim_pivot.global_position.distance_squared_to(flat_target) <= 0.0001:
		return
	aim_pivot.look_at(flat_target, Vector3.UP)
