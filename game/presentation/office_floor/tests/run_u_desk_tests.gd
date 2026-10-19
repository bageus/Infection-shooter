extends SceneTree
## A shot-up U desk breaks into large parts that stay on the floor; they do not vanish when their timer ends.

const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const PATH := "res://models/objects/enviroments/08/08_divider_full_U_desk.glb"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	floor_body.collision_layer = 1 | 128
	stage.add_child(floor_body)
	var effects := Node3D.new()
	stage.add_child(effects)
	var desk := PROP.instantiate() as RigidBody3D
	desk.set("model_path", PATH)
	stage.add_child(desk)
	desk.global_position = Vector3(0, 0.05, 0)
	desk.call("configure_world", effects, null)
	for i in 5:
		await physics_frame
	for hit in 3:
		desk.call("take_projectile_hit", 60.0, Vector3(0, 0.8, 0), Vector3.UP, Vector3.FORWARD, "RIFLE")
		for i in 6:
			await physics_frame
	_expect(bool(desk.get("_broken")), "The U desk breaks after repeated hits")
	var parts := get_nodes_in_group("fallen_environment_fragment").size()
	_expect(parts > 0, "Breaking the U desk leaves large parts")
	for i in 30 * 20:
		await physics_frame
	_expect(get_nodes_in_group("fallen_environment_fragment").size() == parts, "Large parts of the U desk stay after their timer ends")
	print("U desk tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
