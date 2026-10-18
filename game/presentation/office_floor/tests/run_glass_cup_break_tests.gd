extends SceneTree
## A shot drinking glass breaks into its own pieces instead of vanishing with only shard decals left.

const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const MODELS := ["res://models/objects/enviroments/09/09_glass.glb", "res://models/objects/enviroments/09/09_glass_2.glb"]
var failures := 0
var stage: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
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
	await physics_frame
	await physics_frame
	var meshes: Array = prop.get("_shape_meshes")
	_check(meshes.size() == 1, "%s is a single glass mesh" % model.get_file())
	if meshes.is_empty():
		return
	prop.call("take_projectile_hit_at_shape", 28.0, prop.global_position + Vector3.UP * 0.1, Vector3.BACK, Vector3.FORWARD, "AK", 0)
	await physics_frame
	await physics_frame
	var pieces := 0
	for child in effects.get_children():
		if child.name.begins_with("Fragment_") and _carries_mesh(child, (meshes[0] as MeshInstance3D).mesh):
			pieces += 1
	_check(pieces >= 1, "%s breaks into pieces of its own glass (%d)" % [model.get_file(), pieces])
	_check(not (meshes[0] as MeshInstance3D).is_visible_in_tree(), "%s no longer stands whole" % model.get_file())
	_check(prop.collision_layer == 0, "%s stops blocking once broken" % model.get_file())
	prop.queue_free()
	effects.queue_free()
	await process_frame


func _carries_mesh(fragment: Node, wanted: Mesh) -> bool:
	for child in fragment.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh == wanted:
			return true
	return false


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
	print(("PASS: " if condition else "FAIL: ") + label)
