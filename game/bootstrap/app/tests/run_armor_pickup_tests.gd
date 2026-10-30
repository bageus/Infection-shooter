extends SceneTree
## Armor plate: starts absent, is listed in the Items palette, refills the bar on contact,
## and refills again on a new map of the chain only after a plate was found.
const MAIN := preload("res://game/bootstrap/app/main.tscn")
const ARMOR_SCENE := "res://game/features/pickups/public/armor_pickup.tscn"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(320, 180)
	var stage := MAIN.instantiate()
	root.add_child(stage)
	current_scene = stage
	(stage.get_node("Gameplay/Enemies") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	for i in 3:
		await process_frame
	var player := stage.get("player") as Node3D
	player.set_physics_process(false)
	_expect(is_equal_approx(float(player.get("armor")), 0.0), "Player starts without armor")
	_expect(is_equal_approx(float(player.call("export_loadout").get("armor", -1.0)), 0.0), "Carried armor is empty at start")

	var catalog: RefCounted = stage.get("planning_mode").get("catalog")
	var entry := {}
	for candidate: Dictionary in catalog.get("item_catalog"):
		if str(candidate["path"]) == ARMOR_SCENE:
			entry = candidate
	_expect(not entry.is_empty() and str(entry["kind"]) == "item", "Items palette lists armor")
	var placed: Node3D = catalog.call("_instantiate_asset", ARMOR_SCENE)
	var placed_script := placed.get_script() as Script if placed != null else null
	_expect(placed_script != null and placed_script.resource_path.get_file() == "armor_pickup.gd", "Planner instantiates an armor pickup")
	if placed != null:
		placed.free()

	var pickup := (load(ARMOR_SCENE) as PackedScene).instantiate() as Node3D
	stage.add_child(pickup)
	pickup.global_position = player.global_position + Vector3(3.0, 0.0, 0.0)
	await process_frame
	_expect(is_instance_valid(pickup), "Armor waits while the player is away")
	pickup.global_position = player.global_position + Vector3(0.4, 0.0, 0.0)
	for i in 3:
		await process_frame
	_expect(float(player.get("armor")) >= float(player.get("max_armor")) - 0.01, "Walking through armor fills the bar")
	_expect(not is_instance_valid(pickup), "Collected armor leaves the world")
	_expect(is_equal_approx(float(player.call("export_loadout").get("armor", -1.0)), float(player.get("max_armor"))), "Found plate is carried")

	player.set("armor", 40.0)
	var carried: Dictionary = player.call("export_loadout")
	player.set("armor", 0.0)
	player.call("import_loadout", carried)
	_expect(is_equal_approx(float(player.get("armor")), 40.0), "Next map keeps the current armor value")

	stage.queue_free()
	await process_frame
	print("Armor pickup tests: %d failure(s)." % failures)
	quit(1 if failures > 0 else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
		print("FAIL: ", label)
