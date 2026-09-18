extends CharacterBody3D

@export var move_speed: float = 6.0
@export var gravity_acceleration: float = 24.0

@onready var camera: Camera3D = $CameraRig/Camera3D


func _physics_process(delta: float) -> void:
	var input_vector := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)

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
