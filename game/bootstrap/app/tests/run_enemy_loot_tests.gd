extends SceneTree
const CONFIG := preload("res://game/features/pickups/public/loot_config.gd")
const TABLE := preload("res://game/features/pickups/public/drop_table.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var expected := {"ammo_pistol":0.75, "ammo_uzi":0.60, "ammo_shotgun":0.60, "ammo_automate":0.60, "ammo_sniper":0.15, "ammo_minigun":0.30, "medkit":1.0, "antidote":0.35}
	var weights := CONFIG.AUTO_WEIGHTS.duplicate()
	weights.erase("dna")
	_check(weights == expected, "Enemy weights match owner-approved distribution")
	var counts := {}
	for i in 10000:
		var id := CONFIG.weighted_item((float(i) + 0.5) / 10000.0, weights)
		counts[id] = int(counts.get(id, 0)) + 1
	for id: String in expected:
		_check(absf(float(counts.get(id, 0)) / 10000.0 - expected[id] / 4.35) < 0.001, "Correct probability and reachable category: " + id)
		_check(TABLE.SCENES.has(id), "Each weighted id has an existing pickup scene: " + id)
	var stage := Node3D.new()
	root.add_child(stage)
	var persistent := Node3D.new()
	persistent.set_meta(&"persistent_loot", true)
	stage.add_child(persistent)
	persistent.add_to_group(TABLE.DROP_GROUP)
	for _i in TABLE.MAX_DROPS:
		var drop := Node3D.new()
		stage.add_child(drop)
		drop.add_to_group(TABLE.DROP_GROUP)
	var table := TABLE.new()
	stage.add_child(table)
	_check(table.any_drop_chance == 0.65, "Default drop chance stays65%")
	table.any_drop_chance = 1.0
	for i in 8:
		var before := stage.get_child_count()
		table.drop_for_enemy(stage, Vector3(i * 2, 1, 0))
		_check(stage.get_child_count() == before + 1, "Exactly one pickup per kill")
		var live := get_nodes_in_group(TABLE.DROP_GROUP).filter(func(n: Node) -> bool: return not n.is_queued_for_deletion() and not n.has_meta(&"persistent_loot"))
		_check(live.size() == TABLE.MAX_DROPS, "Same-frame kills retain at most40 live temporary drops")
	_check(not persistent.is_queued_for_deletion(), "Authored persistent loot is preserved")
	stage.queue_free()
	await process_frame
	await process_frame
	print("Enemy loot tests: %d failures" % failures)
	quit(failures)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
