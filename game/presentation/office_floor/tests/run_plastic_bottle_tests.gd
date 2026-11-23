extends SceneTree
## A shot plastic bottle flies off its surface instead of barely sliding.

const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const MODEL := "res://models/objects/enviroments/09/glass_mug/09_plastic_water_bottle_blue_500ml.glb"
const FLOOR_TOP := 0.0135
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var ground := StaticBody3D.new()
	ground.collision_layer = 3
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	shape.shape = box
	shape.position.y = FLOOR_TOP - 0.5
	ground.add_child(shape)
	stage.add_child(ground)
	var effects := Node3D.new()
	stage.add_child(effects)
	var bottle := PROP.instantiate() as RigidBody3D
	bottle.set("model_path", MODEL)
	stage.add_child(bottle)
	bottle.position = Vector3(0, FLOOR_TOP + 0.5, 0)
	bottle.call("configure_world", effects, null)
	for frame in 60:
		await physics_frame
	var start := bottle.global_position
	bottle.call("take_projectile_hit", 40.0, bottle.global_position, Vector3.UP, Vector3.FORWARD, "PISTOL")
	await physics_frame
	_expect(bottle.linear_velocity.length() > 1.0, "plastic bottle flies off after a hit (speed %.2f m/s)" % bottle.linear_velocity.length())
	for frame in 60:
		await physics_frame
	var moved := bottle.global_position.distance_to(start)
	_expect(moved > 0.3, "plastic bottle travels after a hit (moved %.2f m)" % moved)
	print("Plastic bottle tests: %d failure(s)." % failures)
	quit(1 if failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
