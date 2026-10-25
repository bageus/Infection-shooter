extends SceneTree
## The planner's Items palette offers all seven ammo boxes, and each one places as a collectable pickup.
const MAIN := preload("res://game/bootstrap/app/main.tscn")
const PICKUP_SCRIPT_NAME := "pickup_item.gd"
const PICKUP_DIR := "res://game/features/pickups/public/"
const BOX_SCENES := [
	"ammo_pistol_pickup.tscn",
	"ammo_uzi_pickup.tscn",
	"ammo_shotgun_pickup.tscn",
	"ammo_automate_pickup.tscn",
	"ammo_sniper_pickup.tscn",
	"ammo_minigun_pickup.tscn",
	"ammo_grenade_pickup.tscn",
]
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(320, 180)
	var stage := MAIN.instantiate()
	# This regression supplies its own fixtures; full authored-map coverage runs separately.
	stage.set("defer_layout_loading", true)
	root.add_child(stage)
	current_scene = stage
	(stage.get_node("Gameplay/Enemies") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	(stage.get("player") as Node3D).set_physics_process(false)
	var planner: Node = stage.get("planning_mode")
	var catalog: RefCounted = planner.get("catalog")
	var items: Array = catalog.get("item_catalog")
	for scene_name: String in BOX_SCENES:
		var path := PICKUP_DIR + scene_name
		var entry := {}
		for candidate: Dictionary in items:
			if str(candidate["path"]) == path:
				entry = candidate
		_expect(not entry.is_empty(), "Items palette lists " + scene_name)
		if entry.is_empty():
			continue
		_expect(str(entry["kind"]) == "item", "Palette entry is an item: " + scene_name)
		var node: Node3D = catalog.call("_instantiate_asset", path)
		_expect(node != null, "Planner instantiates " + scene_name)
		if node == null:
			continue
		var script := node.get_script() as Script
		_expect(node is Area3D and script != null and script.resource_path.get_file() == PICKUP_SCRIPT_NAME, "Placed box is a pickup: " + scene_name)
		node.free()
	stage.queue_free()
	await process_frame
	print("Item palette ammo tests: %d failure(s)." % failures)
	quit(1 if failures > 0 else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
		print("FAIL: ", label)
