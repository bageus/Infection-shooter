extends SceneTree
## A shot drinking glass is removed completely, leaving only actual floor decals (owner update25.10).

const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const FLOOR := preload("res://game/presentation/office_floor/public/base_floor_renderer.gd")
const MODELS := ["res://models/objects/enviroments/09/09_glass.glb", "res://models/objects/enviroments/09/09_glass_2.glb"]
var failures := 0
var stage: Node3D
var floor_view: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	floor_view = FLOOR.new()
	stage.add_child(floor_view)
	for model in MODELS:
		await _shoot_glass(model)
	stage.queue_free()
	await process_frame
	print("Glass cup break tests: %d failure(s)." % failures)
	quit(failures)


func _shoot_glass(model: String) -> void:
	var effects := Node3D.new()
	stage.add_child(effects)
	var prop: RigidBody3D = PROP.instantiate()
	prop.set("model_path", model)
	stage.add_child(prop)
	prop.position = Vector3(0, 0.02, 0)
	prop.call("configure_world", effects, null)
	prop.call("configure_glass_debris", floor_view)
	await physics_frame
	await physics_frame
	var meshes: Array = prop.get("_shape_meshes")
	_check(meshes.size() == 1, "%s is a single glass mesh" % model.get_file())
	if meshes.is_empty():
		return
	prop.call("take_projectile_hit_at_shape", 28.0, prop.global_position + Vector3.UP * 0.1, Vector3.BACK, Vector3.FORWARD, "AK", 0)
	await physics_frame
	await physics_frame
	var pieces := effects.get_children().filter(func(child: Node) -> bool: return child is RigidBody3D)
	_check(pieces.is_empty(), "%s leaves no physical whole-mesh copies" % model.get_file())
	_check(not is_instance_valid(meshes[0]) and not is_instance_valid(prop), "%s removes its visual and collision body" % model.get_file())
	var bake: RefCounted = floor_view.get("_glass")
	_check(not bake.queue.is_empty() or not bake.tiles.is_empty(), "%s leaves real bounded floor decals" % model.get_file())
	floor_view.call("clear_glass_debris")
	effects.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
	print(("PASS: " if condition else "FAIL: ") + label)
