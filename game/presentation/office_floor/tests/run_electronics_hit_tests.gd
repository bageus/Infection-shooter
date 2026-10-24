extends SceneTree
## A shot monitor keeps its collision (its glass screen no longer disables the only
## shape, which dropped it through the desk) and server racks do not glow white.
const PROP_SCENE := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const MONITORS := [
	"res://models/objects/enviroments/05/05_monitor4_server_destructible.glb",
	"res://models/objects/enviroments/05/05_monitor2_destructible.glb",
	"res://models/objects/enviroments/05/05_laptop2_destructible.glb",
]
const RACK_MATERIAL := "res://models/objects/enviroments/03/materials/group03_emission.tres"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var desk := StaticBody3D.new()
	desk.collision_layer = 3
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 0.2, 6)
	shape.shape = box
	desk.add_child(shape)
	stage.add_child(desk)
	desk.position.y = -0.1
	var effects := Node3D.new()
	stage.add_child(effects)
	for model: String in MONITORS:
		var prop := PROP_SCENE.instantiate() as RigidBody3D
		prop.set("model_path", model)
		prop.collision_mask = 3
		stage.add_child(prop)
		prop.global_position = Vector3(0, 0.05, 0)
		prop.call("configure_world", effects, null)
		for i in 30:
			await physics_frame
		var rest_y := prop.global_position.y
		var sparks_before := effects.get_child_count()
		for index in prop.shape_owner_get_shape_count(0) + prop.get_shape_owners().size() - 1:
			prop.call("take_projectile_hit_at_shape", 19.0, prop.global_position + Vector3(0, 0.1, 0.1), Vector3.BACK, Vector3.FORWARD, "PISTOL", index)
		for i in 60:
			await physics_frame
		var live := 0
		for child in prop.get_children():
			if child is CollisionShape3D and not child.disabled:
				live += 1
		var name := model.get_file()
		_check(live > 0, "%s keeps an active collision shape after a hit." % name)
		_check(prop.global_position.y > rest_y - 0.05, "%s stays on its support after a hit (%.3f m)." % [name, prop.global_position.y - rest_y])
		_check(effects.get_child_count() > sparks_before, "%s sparks when shot." % name)
		prop.queue_free()
		await process_frame
	var rack := load(RACK_MATERIAL) as BaseMaterial3D
	_check(rack.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY, "Lit server racks multiply the emission map, so unlit areas stay dark.")
	stage.queue_free()
	await process_frame
	print("Electronics hit tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
