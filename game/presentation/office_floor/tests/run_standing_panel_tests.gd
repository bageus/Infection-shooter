extends SceneTree
## A blast must not leave a divider's panels standing as an intact-looking wall that characters walk through,
## and a piece lying on other debris must not be shoved again once it rests.

const DAMAGE := preload("res://game/presentation/office_floor/environment_damage.gd")
const FRAGMENT := preload("res://game/presentation/office_floor/environment_fragment.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 2
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(20, 0.2, 20)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	stage.add_child(floor_body)
	floor_body.position.y = -0.1 + 0.0135
	var panel := _piece(stage, Vector3(1.5, 1.6, 0.05), Vector3(0, 0.81, 0))
	panel.topple_from(Vector3(1.5, 1.6, 0.05), Vector3(0, 0.8, 2), Vector3.BACK)
	var block := _piece(stage, Vector3(0.6, 0.6, 0.6), Vector3(4, 0.31, 0))
	block.topple_from(Vector3(0.6, 0.6, 0.6), Vector3(4, 0.3, 2), Vector3.BACK)
	_check(block.linear_velocity.is_zero_approx() and block.angular_velocity.is_zero_approx(), "A chunky block is not pushed over")
	await create_timer(3.0).timeout
	_check(panel.global_basis.y.angle_to(Vector3.UP) > deg_to_rad(60.0), "A thin standing panel is knocked over by the blast")
	# A piece resting tilted on other debris is not unstuck any more; only one on its edge is.
	var propped := _piece(stage, Vector3(0.8, 0.1, 0.8), Vector3(8, 0.9, 0))
	propped.freeze = true
	await physics_frame
	propped.sleeping = true
	_check(not propped.unstick(), "A flat piece lying on debris is not shoved when it rests")
	stage.queue_free()
	await process_frame
	print("Standing panel tests: %d failure(s)." % failures)
	quit(failures)


func _piece(stage: Node3D, size: Vector3, at: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.set_script(FRAGMENT)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	body.add_child(visual)
	stage.add_child(body)
	body.global_position = at
	body.mass = 1.0
	return body


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
	print(("PASS: " if condition else "FAIL: ") + label)
