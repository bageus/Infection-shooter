extends SceneTree
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const SHADOWS := preload("res://game/presentation/office_floor/prop_shadow_policy.gd")
const MODELS := "res://models/objects/enviroments/"
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var small := _prop(stage, "09/09_book_small.glb")
	var bottle := _prop(stage, "09/09_plastic_water_bottle_blue_500ml.glb")
	var large := _prop(stage, "06/06_simple_chair.glb")
	var wall := _prop(stage, "01/01_column.glb")
	await process_frame
	_check(_all_off(small), "Small book meshes do not cast shadows")
	_check(_all_off(bottle), "Small bottle meshes do not cast shadows")
	_check(_has_shadow(large), "Large chair retains its shadows, including its small mesh components")
	wall.scale = Vector3.ONE * .05
	await process_frame
	_check(_has_shadow(wall), "Structural geometry keeps shadows regardless of its scaled AABB")
	small.scale = Vector3.ONE * 5.0
	await process_frame
	_check(_has_shadow(small), "Planner enlargement restores original mesh shadow settings")
	small.scale = Vector3.ONE
	await process_frame
	_check(_all_off(small), "Planner shrinking reapplies the small-object rule")
	var geometry: RefCounted = small.get("_geometry")
	var lazy := MeshInstance3D.new()
	lazy.mesh = BoxMesh.new()
	small.get_node("Visual").add_child(lazy)
	geometry.get("shadows").apply_loaded_group(lazy)
	_check(lazy.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Lazily loaded damage geometry inherits the owning prop's policy")
	var authored_off := MeshInstance3D.new()
	authored_off.mesh = BoxMesh.new()
	authored_off.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	small.get_node("Visual").add_child(authored_off)
	geometry.get("shadows").apply_loaded_group(authored_off)
	small.scale = Vector3.ONE * 5.0
	await process_frame
	_check(authored_off.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Scale restoration preserves authored OFF settings")
	stage.queue_free()
	await process_frame
	await process_frame
	print("Prop shadow tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _prop(stage: Node3D, model: String) -> RigidBody3D:
	var prop := PROP.instantiate() as RigidBody3D
	prop.set("model_path", MODELS + model)
	stage.add_child(prop)
	prop.freeze = true
	return prop

func _all_off(prop: Node) -> bool:
	var meshes := prop.get_node("Visual").find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return false
	for mesh in meshes:
		if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			return false
	return true

func _has_shadow(prop: Node) -> bool:
	for mesh in prop.get_node("Visual").find_children("*", "MeshInstance3D", true, false):
		if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			return true
	return false

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
