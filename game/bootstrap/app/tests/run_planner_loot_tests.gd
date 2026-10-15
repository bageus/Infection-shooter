extends SceneTree
## Planner loot and enemy-stat options: panel, drops, undo and map round trip.
const MAIN := preload("res://game/bootstrap/app/main.tscn")
const CONFIG := preload("res://game/features/pickups/public/loot_config.gd")
const CRATE := "res://models/objects/enviroments/04/04_crate_small_broken.glb"
const HUNGER := "res://game/features/infected/public/infected_hunger.tscn"
var failures := 0
var stage: Node3D
var planner: Node
var objects: Node
var controls: Node
var catalog: RefCounted


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(320, 180)
	root.positional_shadow_atlas_size = 256
	RenderingServer.directional_shadow_atlas_set_size(256, true)
	stage = MAIN.instantiate()
	root.add_child(stage)
	current_scene = stage
	(stage.get_node("Gameplay/Enemies") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	var player: Node3D = stage.get("player")
	player.set_physics_process(false)
	planner = stage.get("planning_mode")
	objects = planner.get("objects")
	controls = planner.get("controls")
	catalog = planner.get("catalog")
	_config()
	await _weapon_ammo(player)
	_items_palette()
	await _crate_panel_and_drop()
	await _enemy_stats_and_drop()
	await _round_trip()
	await _dna_pickup(player)
	stage.queue_free()
	await process_frame
	print("Planner loot tests: %d failures" % failures)
	quit(failures)


func _config() -> void:
	var bad := CONFIG.sanitize({"mode": "nonsense", "items": {"medkit": 99, "ghost": 3, "dna": "x", "weapon_7": 1}}, "auto")
	_check(bad["mode"] == "auto", "Unknown mode falls back")
	_check(bad["items"] == {"medkit": CONFIG.MAX_COUNT, "weapon_7": 1}, "Counts clamp and unknown ids drop")
	_check(CONFIG.sanitize(null, "empty")["mode"] == "empty", "Missing config uses the fallback mode")
	var stats := CONFIG.sanitize_stats({"health": 10, "damage": 999})
	_check(stats["health"] == 50.0 and stats["damage"] == 200.0, "Stats clamp to 50-200")
	_check(CONFIG.sanitize_stats(null) == {"health": 100.0, "damage": 100.0}, "Stats default to 100")
	for size in ["small", "large"]:
		_check(not CONFIG.auto_list(size).is_empty(), "Auto loot is never empty: " + size)


func _weapon_ammo(player: Node3D) -> void:
	var drops := preload("res://game/features/pickups/public/loot_drop.gd")
	var expected := {"ammo_automate": [4, 30], "ammo_sniper": [6, 8], "ammo_minigun": [7, 100]}
	for id: String in expected:
		var config := CONFIG.sanitize({"mode":"manual", "items":{id:1}})
		_check(config["items"].get(id) == 1, "Manual ammo survives sanitization: " + id)
		var weapon: Node = player.get("weapons")[expected[id][0]]
		weapon.set("_reserve_ammo", 0)
		var item := (drops.SCENES[id] as PackedScene).instantiate()
		stage.add_child(item)
		item.call("_on_body_entered", player)
		_check(weapon.get("_reserve_ammo") == expected[id][1], "Pickup feeds correct weapon: " + id)
		_check(item.is_queued_for_deletion(), "Accepted ammo is consumed")
		await process_frame
	# A shared box feeds M4 when AK is already full, and stays when both are full.
	var ak: Node = player.get("weapons")[4]
	var m4: Node = player.get("weapons")[5]
	ak.set("_reserve_ammo", ak.get("max_reserve_ammo"))
	m4.set("_reserve_ammo", 0)
	var shared := (drops.SCENES["ammo_automate"] as PackedScene).instantiate()
	stage.add_child(shared)
	shared.call("_on_body_entered", player)
	_check(m4.get("_reserve_ammo") == 30, "Shared box falls back from full AK to M4")
	await process_frame
	m4.set("_reserve_ammo", m4.get("max_reserve_ammo"))
	shared = (drops.SCENES["ammo_automate"] as PackedScene).instantiate()
	stage.add_child(shared)
	shared.call("_on_body_entered", player)
	_check(not shared.is_queued_for_deletion(), "Full reserves leave ammo on the floor")
	shared.queue_free()


func _items_palette() -> void:
	controls.call("_show_item_catalog")
	var names: Array[String] = []
	for entry: Dictionary in catalog.item_catalog:
		var node: Node3D = catalog.call("_instantiate_asset", str(entry["path"]))
		_check(node != null, "Palette item instantiates: " + str(entry["name"]))
		if node != null:
			node.free()
		names.append(str(entry["name"]))
	for expected in ["Ключ", "ДНК", "Аптечка", "Антидот"]:
		_check(expected in names, "Palette lists " + expected)
	_check(controls.get("palette").item_count == catalog.item_catalog.size(), "Items tab fills the palette")


func _place(path: String, at: Vector3) -> Node3D:
	var node: Node3D = catalog.call("_instantiate_asset", path)
	var parent: Node = stage.get("enemies") if path == HUNGER else planner.get("root")
	parent.add_child(node)
	node.global_position = at
	node.set_meta("planning_scene_path", path)
	if path == HUNGER:
		node.set_meta("planning_actor_kind", "enemy")
	(objects.get("placed") as Array).append(node)
	return node


func _crate_panel_and_drop() -> void:
	var crate := _place(CRATE, Vector3(30, 0.5, -20))
	await process_frame
	_check(crate.call("has_loot"), "A crate has loot options")
	_check(crate.call("get_loot_config")["mode"] == "empty", "Existing crates stay empty")
	objects.call("_select", crate)
	var options: Node = controls.get("loot_options")
	_check(options.get("panel").visible, "Selecting a crate opens its contents panel")
	_check(not options.get("stats_box").visible, "A crate has no enemy stats")
	var mode: OptionButton = options.get("mode")
	mode.select(1)
	mode.item_selected.emit(1)
	(options.get("item_spins")["medkit"] as SpinBox).value = 2
	(options.get("item_spins")["weapon_3"] as SpinBox).value = 1
	var config: Dictionary = crate.call("get_loot_config")
	_check(config["mode"] == "manual" and config["items"] == {"medkit": 2, "weapon_3": 1}, "Panel writes the crate contents")
	planner.get("edit_history").call("undo")
	_check(crate.call("get_loot_config")["items"] == {"medkit": 2}, "Undo steps back one panel edit")
	(options.get("item_spins")["weapon_3"] as SpinBox).value = 1
	var weapons: Array[Vector3] = []
	var drop_weapon := func(index: int, at: Vector3) -> bool:
		weapons.append(Vector3(index, at.x, at.z))
		return true
	crate.call("configure_loot_drop", drop_weapon)
	var world: Node3D = Node3D.new()
	stage.add_child(world)
	crate.call("configure_world", world, null)
	for _hit in 40:
		if not is_instance_valid(crate) or crate.get("_broken"):
			break
		crate.call("take_projectile_hit", 80.0, crate.global_position, Vector3.UP, Vector3.DOWN, "GRENADE")
		await process_frame
	await process_frame
	var medkits := world.get_children().filter(func(node: Node) -> bool: return node.get("pickup_type") == 0)
	_check(medkits.size() == 2, "A broken crate drops its medkits (%d)" % medkits.size())
	_check(weapons.size() == 1 and int(weapons[0].x) == 3, "A broken crate hands its weapon to the mission")
	var plain := _place(CRATE, Vector3(33, 0.5, -20))
	var quiet: Node3D = Node3D.new()
	stage.add_child(quiet)
	plain.call("configure_world", quiet, null)
	for _hit in 40:
		plain.call("take_projectile_hit", 80.0, plain.global_position, Vector3.UP, Vector3.DOWN, "GRENADE")
		await process_frame
	_check(quiet.get_children().filter(func(node: Node) -> bool: return node.get("pickup_type") != null).is_empty(), "A crate without loot settings drops nothing, as before")
	objects.call("_select", null)
	world.queue_free()
	quiet.queue_free()


func _enemy_stats_and_drop() -> void:
	var enemy := _place(HUNGER, Vector3(36, 1.0, -20))
	await process_frame
	var base_health := float(enemy.get("max_health"))
	var base_damage := float(enemy.get("attack_damage"))
	objects.call("_select", enemy)
	var options: Node = controls.get("loot_options")
	_check(options.get("panel").visible and options.get("stats_box").visible, "Selecting an infected opens loot and stats")
	(options.get("health") as SpinBox).value = 150
	(options.get("damage") as SpinBox).value = 50
	_check(is_equal_approx(float(enemy.get("max_health")), base_health * 1.5) and is_equal_approx(float(enemy.get("health")), base_health * 1.5), "Toughness 150% scales health")
	_check(is_equal_approx(float(enemy.get("attack_damage")), base_damage * 0.5), "Damage 50% scales the attack")
	(options.get("health") as SpinBox).value = 500
	_check(is_equal_approx(float(enemy.get("max_health")), base_health * 2.0), "Toughness is capped at 200%")
	(options.get("health") as SpinBox).value = 100
	(options.get("damage") as SpinBox).value = 100
	_check(is_equal_approx(float(enemy.get("max_health")), base_health) and is_equal_approx(float(enemy.get("attack_damage")), base_damage), "100% restores the base values")
	var mode: OptionButton = options.get("mode")
	mode.select(1)
	mode.item_selected.emit(1)
	(options.get("item_spins")["antidote"] as SpinBox).value = 3
	enemy.call("configure_stats", {"health": 100, "damage": 100})
	var world: Node3D = Node3D.new()
	stage.add_child(world)
	enemy.set("effects_root", world)
	enemy.call("take_damage", 100000.0)
	await process_frame
	var antidotes := world.get_children().filter(func(node: Node) -> bool: return node.get("pickup_type") == 4)
	_check(antidotes.size() == 3, "An infected drops exactly its authored loot (%d)" % antidotes.size())
	objects.call("_select", null)
	world.queue_free()
	var silent := _place(HUNGER, Vector3(38, 1.0, -20))
	silent.call("configure_loot", {"mode": "empty"})
	var quiet: Node3D = Node3D.new()
	stage.add_child(quiet)
	silent.set("effects_root", quiet)
	for _i in 8:
		silent.call("take_damage", 100000.0)
		await process_frame
	_check(quiet.get_children().filter(func(node: Node) -> bool: return node.get("pickup_type") != null).is_empty(), "Empty mode drops nothing")
	quiet.queue_free()


func _round_trip() -> void:
	var crate := _place(CRATE, Vector3(30, 0.5, -10))
	crate.call("configure_loot", {"mode": "auto"})
	var enemy := _place(HUNGER, Vector3(33, 1.0, -10))
	enemy.call("configure_stats", {"health": 75, "damage": 125})
	enemy.call("configure_loot", {"mode": "manual", "items": {"dna": 1, "weapon_6": 1}})
	var plain := _place(CRATE, Vector3(36, 0.5, -10))
	var data: Dictionary = planner.get("storage").call("_collect_layout_data")
	var records: Array = data["objects"].filter(func(r: Dictionary) -> bool: return r["scene"] in [CRATE, HUNGER] and is_equal_approx(float(r["z"]), -10.0))
	_check(records.size() == 3, "The three test objects are saved")
	_check(records[0]["loot"] == {"mode": "auto", "items": {}}, "Crate loot is saved")
	_check(records[1]["enemy_stats"] == {"health": 75.0, "damage": 125.0} and records[1]["loot"]["items"] == {"dna": 1, "weapon_6": 1}, "Infected loot and stats are saved")
	_check(not records[2].has("loot"), "An untouched crate saves no loot, so old maps stay byte-compatible")
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	var result: Dictionary = objects.call("_apply_layout_data", parsed)
	_check(int(result.get("loaded", 0)) > 0 and not result.has("error"), "A map with loot loads")
	await process_frame
	var back_crate := _nearest(CRATE, Vector2(30, -10))
	var back_enemy := _nearest(HUNGER, Vector2(33, -10))
	var back_plain := _nearest(CRATE, Vector2(36, -10))
	_check(back_crate != null and back_crate.call("get_loot_config")["mode"] == "auto", "Crate loot survives a reload")
	_check(back_enemy != null and back_enemy.call("get_enemy_stats") == {"health": 75.0, "damage": 125.0}, "Infected stats survive a reload")
	_check(back_enemy != null and is_equal_approx(float(back_enemy.get("max_health")), 45.0 * 0.75), "Reloaded infected is built with the saved toughness")
	_check(back_enemy.call("get_loot_config")["items"] == {"dna": 1, "weapon_6": 1}, "Infected loot survives a reload")
	_check(back_plain != null and not back_plain.has_meta("planning_loot"), "Old crate record loads without loot")
	var legacy: Dictionary = {"version": 8, "objects": [{"scene": HUNGER, "x": 30, "y": 1, "z": -5}, {"scene": CRATE, "x": 33, "y": 0.5, "z": -5}]}
	_check(not objects.call("_apply_layout_data", legacy).has("error"), "A map saved before these options still loads")
	var broken := {"version": 8, "objects": [{"scene": CRATE, "loot": "oops"}]}
	_check(objects.call("_apply_layout_data", broken).has("error"), "A malformed loot field is rejected")


func _nearest(scene: String, at: Vector2) -> Node3D:
	var best: Node3D
	var best_distance := 1.5
	for node: Node3D in objects.get("placed"):
		if is_instance_valid(node) and str(node.get_meta("planning_scene_path", "")) == scene:
			var distance := Vector2(node.position.x, node.position.z).distance_to(at)
			if distance < best_distance:
				best = node
				best_distance = distance
	return best


func _dna_pickup(player: Node3D) -> void:
	var scene: PackedScene = load("res://game/features/pickups/public/dna_pickup.tscn")
	var pickup: Node = scene.instantiate()
	stage.add_child(pickup)
	var runtime: Node = player.get("infection_runtime")
	var before: float = runtime.call("get_mutation")
	pickup.call("_on_body_entered", player)
	await process_frame
	_check(not is_instance_valid(pickup) or pickup.is_queued_for_deletion(), "A DNA pickup is consumed on touch")
	_check(runtime.call("get_mutation") <= before, "DNA does not raise the mutation level")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)
