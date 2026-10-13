extends SceneTree
## Every ammo box placed in the planner stays a collectable pickup after a save and reload,
## including maps saved while the box was still stored as its .glb model path.
const MAIN := preload("res://game/bootstrap/app/main.tscn")
const PICKUP_SCRIPT_NAME := "pickup_item.gd"
const AMMO_WEAPONS_TYPE := 6 # PickupType.AMMO_WEAPONS
const MODEL_DIR := "res://models/objects/enviroments/12/"
const BOXES := {
	"12_ammo_pistols.glb": ["PISTOL"],
	"12_ammo_uzi.glb": ["UZI"],
	"12_ammo_shotgun.glb": ["SHOTGUN"],
	"12_ammo_automate.glb": ["AK", "M4"],
	"12_ammo_minigun.glb": ["MINIGUN"],
	"12_ammo_sniper.glb": ["SNIPER RIFLE"],
}
var failures := 0
var stage: Node3D
var planner: Node
var objects: Node
var catalog: RefCounted


## Stands in for the player: takes ammo for the named weapons only.
class Collector extends Node3D:
	var accepts: Array[String] = []
	var received: Array[String] = []

	func add_ammo_for_weapon(weapon_name: String, amount: int) -> int:
		if not accepts.has(weapon_name):
			return 0
		received.append("%s:%d" % [weapon_name, amount])
		return amount


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(320, 180)
	stage = MAIN.instantiate()
	root.add_child(stage)
	current_scene = stage
	(stage.get_node("Gameplay/Enemies") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	(stage.get("player") as Node3D).set_physics_process(false)
	planner = stage.get("planning_mode")
	objects = planner.get("objects")
	catalog = planner.get("catalog")
	await _check_placed_from_catalog()
	await _check_legacy_model_paths()
	stage.queue_free()
	await process_frame
	print("Placed ammo pickup tests: %d failure(s)." % failures)
	quit(1 if failures > 0 else 0)


func _catalog_entry(file_name: String) -> Dictionary:
	for entry: Dictionary in catalog.group_catalogs["12"]:
		if str(entry["name"]) == file_name.get_basename().replace("_", " "):
			return entry
	return {}


# Places each box the way the planner does (catalog entry, instantiate, tag, track),
# saves through the real collector, reloads through the real loader.
func _check_placed_from_catalog() -> void:
	var index := 0
	for file_name: String in BOXES:
		var entry := _catalog_entry(file_name)
		_expect(not entry.is_empty(), "Catalog lists " + file_name)
		if entry.is_empty():
			continue
		var path := str(entry["path"])
		var node: Node3D = catalog.call("_instantiate_asset", path)
		_expect(node != null, "Planner instantiates " + file_name)
		planner.get("root").add_child(node)
		node.global_position = Vector3(40 + index * 3, 0.5, -20)
		node.set_meta("planning_scene_path", path)
		(objects.get("placed") as Array).append(node)
		index += 1
	var data: Dictionary = planner.get("storage").call("_collect_layout_data")
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	var result: Dictionary = objects.call("_apply_layout_data", parsed)
	_expect(not result.has("error"), "The saved layout loads")
	await process_frame
	index = 0
	for file_name: String in BOXES:
		await _expect_collectable(Vector2(40 + index * 3, -20), file_name, "placed")
		index += 1


# Maps written before the catalog mapped pickups (and the shipped base map) hold the model path.
func _check_legacy_model_paths() -> void:
	var records: Array = []
	var index := 0
	for file_name: String in BOXES:
		records.append({"scene": MODEL_DIR + file_name, "x": 40 + index * 3, "y": 0.5, "z": -30})
		index += 1
	var result: Dictionary = objects.call("_apply_layout_data", {"version": 8, "objects": records})
	_expect(not result.has("error"), "A map with .glb ammo boxes loads")
	await process_frame
	index = 0
	for file_name: String in BOXES:
		await _expect_collectable(Vector2(40 + index * 3, -30), file_name, "legacy .glb")
		index += 1


func _expect_collectable(at: Vector2, file_name: String, label: String) -> void:
	var box: Node3D
	for candidate: Variant in objects.get("placed"):
		var node := candidate as Node3D if is_instance_valid(candidate) else null
		if node != null and Vector2(node.position.x, node.position.z).distance_to(at) < 1.0:
			box = node
	var tag := "%s %s" % [label, file_name]
	_expect(box != null, "Restored object exists: " + tag)
	if box == null:
		return
	_expect(box is Area3D and _is_pickup(box), "Restored box is a pickup, not a prop: %s (%s)" % [tag, box.get_class()])
	if not (box is Area3D and _is_pickup(box)):
		return
	var names: PackedStringArray = box.get("weapon_names")
	var expected: Array = BOXES[file_name]
	var weapon := expected[0] as String
	if int(box.get("pickup_type")) == AMMO_WEAPONS_TYPE:
		_expect(Array(names) == expected, "Weapon list is right: " + tag)
	var collector := Collector.new()
	collector.accepts.assign([weapon])
	root.add_child(collector)
	(box as Area3D).body_entered.emit(collector)
	await process_frame
	await process_frame
	_expect(collector.received.size() == 1 and int(collector.received[0].split(":")[1]) > 0, "Walking into the box gives ammo: " + tag)
	_expect(not is_instance_valid(box) or box.is_queued_for_deletion(), "Box is consumed: " + tag)
	collector.queue_free()


func _is_pickup(node: Node) -> bool:
	var script := node.get_script() as Script
	return script != null and script.resource_path.get_file() == PICKUP_SCRIPT_NAME


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
		print("FAIL: ", label)
