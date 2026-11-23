extends SceneTree
## Lab equipment from models/objects/enviroments/05/medical: palette entries, electronics, breakables, anchored and indestructible rules.
const PROP_SCENE := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const FRAGILE := preload("res://game/presentation/office_floor/fragile_prop.gd")
const RECIPE := preload("res://game/presentation/office_floor/prop_debris_recipe.gd")
const RETAINED := preload("res://game/presentation/office_floor/retained_prop_body.gd")
const DAMAGE_STATE := preload("res://game/features/combat/public/prop_damage_state.gd")
const MODEL_PATHS := preload("res://game/core/model_paths/public/model_paths.gd")
const LAB_MODELS := ["Laboratory_Autoclave", "Laboratory_Balance", "Laboratory_Drying_Cabinet", "Laboratory_Flasks_Set", "Laboratory_Fridge",
	"Laboratory_Microscope", "Laboratory_Storage_Cabinet", "Hyperbaric_Chamber", "Medical_Instrument_Cabinet", "Medical_Lab_Oven",
	"MRI_Scanner", "Morgue_Drawers_3x3", "Patient_Monitor_Stand", "Test_Tube_Rack", "Vortex_Mixer", "X_Ray_System",
	"Containment_Tank_No_Subject", "Containment_Tank_hunger"]
const BREAKABLE_MODELS := ["Laboratory_Balance.glb", "Laboratory_Microscope.glb", "Laboratory_Flasks_Set.glb", "Test_Tube_Rack.glb"]

var failures := 0
var stage: Node3D
var effects: Node3D
var floor_view: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_palette()
	_check_rules()
	stage = Node3D.new()
	root.add_child(stage)
	effects = Node3D.new()
	stage.add_child(effects)
	floor_view = _make_floor_view()
	stage.add_child(floor_view)
	for model in BREAKABLE_MODELS:
		await _shoot(model)
	stage.queue_free()
	await process_frame
	print("Lab equipment tests: %d failure(s)." % failures)
	quit(failures)


func _check_palette() -> void:
	var listed := MODEL_PATHS.list("05")
	for model in LAB_MODELS:
		var file: String = model + ".glb"
		_check(MODEL_PATHS.find("05", file) != "", "%s is in the group 05 palette" % file)
		_check(listed.has(MODEL_PATHS.find("05", file)), "%s is listed for the planner" % file)


func _check_rules() -> void:
	var balance := "Laboratory_Balance.glb"
	_check(FRAGILE.applies("res://models/objects/enviroments/05/medical/" + balance), "A balance breaks whole")
	_check(FRAGILE.applies("res://models/objects/enviroments/05/medical/Test_Tube_Rack.glb") and FRAGILE.is_glassware("Test_Tube_Rack.glb"), "A test tube rack is glassware")
	var plastic := RECIPE.for_model(balance, "shatter")
	_check(not plastic.is_empty() and plastic.all(func(kind: String) -> bool: return kind == "plastic"), "A balance leaves plastic decals only")
	var glass := RECIPE.for_model("Laboratory_Flasks_Set.glb", "shatter")
	_check("glass" in glass, "Lab flasks leave glass decals")
	var tank := RECIPE.for_model("Containment_Tank_No_Subject.glb", "shatter")
	_check(not tank.is_empty() and tank.all(func(kind: String) -> bool: return kind == "glass"), "A tank leaves glass decals only")
	_check(FRAGILE.glass_intact("Containment_Tank_hunger.glb") and FRAGILE.glass_intact("Containment_Tank_No_Subject.glb") and not FRAGILE.glass_intact("Laboratory_Fridge.glb"), "Only the tank glass stays whole")

	var fridge := DAMAGE_STATE.new()
	fridge.configure("Laboratory_Fridge.glb", 0, false)
	_check(fridge.category != "tech" and fridge.indestructible, "A fridge is not electronics and is indestructible")
	var autoclave := DAMAGE_STATE.new()
	autoclave.configure("Laboratory_Autoclave.glb", 0, false)
	_check(autoclave.category == "tech", "An autoclave is electronics")
	var mri := DAMAGE_STATE.new()
	mri.configure("MRI_Scanner.glb", 0, false)
	_check(mri.category == "tech" and mri.indestructible, "An MRI scanner sparks and is indestructible")

	var anchored := RETAINED.new()
	for file in ["Laboratory_Fridge.glb", "MRI_Scanner.glb", "X_Ray_System.glb", "Containment_Tank_No_Subject.glb"]:
		_check(anchored.anchored("res://models/objects/enviroments/05/medical/" + file), "%s stays in place" % file)
	_check(not anchored.anchored("res://models/objects/enviroments/05/medical/Hyperbaric_Chamber.glb"), "A hyperbaric chamber can be pushed")


func _shoot(model: String) -> void:
	var prop := PROP_SCENE.instantiate() as RigidBody3D
	prop.set("model_path", MODEL_PATHS.find("05", model))
	prop.collision_mask = 3
	stage.add_child(prop)
	prop.global_position = Vector3(0, 0.02, 0)
	prop.call("configure_world", effects, null)
	prop.call("configure_glass_debris", floor_view)
	for i in 10:
		await physics_frame
	var visual := prop.get_node_or_null("Visual") as Node3D
	var kinds_before: int = floor_view.get("kinds").size()
	prop.call("take_projectile_hit", 5.0, prop.global_position + Vector3.UP * 0.1, Vector3.UP, Vector3.FORWARD, "AK")
	for i in 5:
		await physics_frame
	_check(not is_instance_valid(visual), "%s removes its visual on its first hit" % model)
	_check(not is_instance_valid(prop), "%s removes its physical body once broken" % model)
	_check(floor_view.get("kinds").size() > kinds_before, "%s reports decals to the floor" % model)
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
