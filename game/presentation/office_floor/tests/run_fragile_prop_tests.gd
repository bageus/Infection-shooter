extends SceneTree
## Glassware, fruit and paintings break whole on their first hit from any weapon and report their material decals.
const PROP_SCENE := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const FRAGILE := preload("res://game/presentation/office_floor/fragile_prop.gd")
const RECIPE := preload("res://game/presentation/office_floor/prop_debris_recipe.gd")
const DIR := "res://models/objects/enviroments/09/"
const FRAGILE_MODELS := ["09_mug.glb", "09_mug_alt_2.glb", "09_glass.glb", "09_glass_2.glb", "09_fruit_plate.glb", "09_fruit_apple.glb", "09_book_big.glb", "09_pen_1.glb", "09_painting.glb", "09_painting_small.glb"]
var failures := 0
var stage: Node3D
var effects: Node3D
var floor_view: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_applies()
	_check_recipes()
	stage = Node3D.new()
	root.add_child(stage)
	effects = Node3D.new()
	stage.add_child(effects)
	floor_view = _make_floor_view()
	stage.add_child(floor_view)
	for model in FRAGILE_MODELS:
		for weapon in ["PISTOL", "AK"]:
			await _shoot(model, weapon)
	stage.queue_free()
	await process_frame
	print("Fragile prop tests: %d failure(s)." % failures)
	quit(failures)


func _check_applies() -> void:
	for model in FRAGILE_MODELS:
		_check(FRAGILE.applies(DIR + model), "%s is a fragile item" % model)
	for model in ["09_glass_water_bottle_clear_250ml.glb", "09_book_big.glb", "09_pen_1.glb", "09_fruit_plate_2.glb"]:
		_check(FRAGILE.applies(DIR + model), "%s uses complete small-item disposal" % model)
	_check(not FRAGILE.is_glassware(DIR + "09_painting.glb"), "A painting is not glassware")
	_check(FRAGILE.is_glassware(DIR + "09_fruit_plate_2.glb"), "A fruit plate is glassware")


func _check_recipes() -> void:
	var painting := RECIPE.for_model("09_painting.glb", "shatter")
	for kind in ["paper", "cardboard", "wood"]:
		_check(kind in painting, "A painting leaves %s decals" % kind)
	_check("glass" not in painting, "A painting leaves no glass")
	var mug := RECIPE.for_model("09_mug.glb", "shatter")
	_check("glass" in mug and "plastic" in mug and "paper" not in mug, "A mug leaves glass and plastic decals")
	var fruit := RECIPE.for_model("09_fruit_apple.glb", "shatter")
	_check(not fruit.is_empty() and fruit.all(func(kind: String) -> bool: return kind == "plastic"), "Fruit leaves plastic decals only")


func _shoot(model: String, weapon: String) -> void:
	var prop := PROP_SCENE.instantiate() as RigidBody3D
	prop.set("model_path", DIR + model)
	prop.collision_mask = 3
	stage.add_child(prop)
	prop.global_position = Vector3(0, 0.02, 0)
	prop.call("configure_world", effects, null)
	prop.call("configure_glass_debris", floor_view)
	for i in 10:
		await physics_frame
	var visual := prop.get_node_or_null("Visual") as Node3D
	var kinds_before: int = floor_view.get("kinds").size()
	var pieces_before := effects.get_children().filter(func(node: Node) -> bool: return node is RigidBody3D).size()
	prop.call("take_projectile_hit", 5.0, prop.global_position + Vector3.UP * 0.1, Vector3.UP, Vector3.FORWARD, weapon)
	for i in 5:
		await physics_frame
	var label := "%s by %s" % [model, weapon]
	_check(not is_instance_valid(visual), "%s removes its visual on its first hit" % label)
	_check(not is_instance_valid(prop), "%s removes its physical body once broken" % label)
	_check(effects.get_children().filter(func(node: Node) -> bool: return node is RigidBody3D).size() == pieces_before, "%s leaves decals without loose pieces" % label)
	_check(floor_view.get("kinds").size() > kinds_before, "%s reports decals to the floor" % label)
	for piece in effects.get_children():
		piece.queue_free()
	floor_view.set("kinds", [])
	if is_instance_valid(prop): prop.queue_free()
	await process_frame


func _make_floor_view() -> Node3D:
	var script := GDScript.new()
	script.source_code = "extends Node3D\nvar kinds: Array = []\nfunc scatter_prop_debris(_at: Vector3, _footprint: Vector2, recipe: Array[String], _direction: Vector3, _excluded: Array[RID] = []) -> void:\n\tkinds.append_array(recipe)\n"
	script.reload()
	var view := Node3D.new()
	view.set_script(script)
	return view


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
	print(("PASS: " if condition else "FAIL: ") + label)
