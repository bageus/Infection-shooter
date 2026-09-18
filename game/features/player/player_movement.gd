extends CharacterBody3D

@export var move_speed: float = 6.0
@export var gravity_acceleration: float = 24.0
@export var max_health: float = 100.0

@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var aim_pivot: Node3D = $AimPivot
@onready var weapon: Node3D = $AimPivot/PrototypeRifle

var health: float


func _ready() -> void:
	health = max_health


func _physics_process(delta: float) -> void:
	_update_aim()
	_update_movement(delta)
	if Input.is_action_pressed("fire"):
		weapon.call("try_fire")


func take_damage(amount: float) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	health = maxf(0.0, health - amount)


func _update_movement(delta: float) -> void:
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
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity_acceleration * delta
	move_and_slide()


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
