extends RefCounted
## Spawns authored loot (see loot_config.gd) around a point on the floor.

const CONFIG := preload("res://game/features/pickups/public/loot_config.gd")
const DROP_TABLE := preload("res://game/features/pickups/public/drop_table.gd")
const SCENES := DROP_TABLE.SCENES


## Crate contents on destruction. `empty` drops nothing, `auto` rolls by crate size.
static func release_crate(world: Node, at: Vector3, config: Dictionary, size_hint: String, drop_weapon: Callable) -> void:
	match str(config.get("mode", "empty")):
		"manual":
			spawn(world, CONFIG.manual_list(config), at, drop_weapon)
		"auto":
			spawn(world, CONFIG.auto_list(size_hint), at, drop_weapon)


## Infected death. Without a config the classic random drop applies.
static func release_enemy(world: Node, at: Vector3, raw_config: Variant, drop_weapon: Callable) -> void:
	var config := CONFIG.sanitize(raw_config, "auto")
	match str(config["mode"]):
		"manual":
			spawn(world, CONFIG.manual_list(config), at, drop_weapon)
		"auto":
			var table := DROP_TABLE.new()
			world.add_child(table)
			table.call("drop_for_enemy", world, at)
			table.queue_free()


static func spawn(world: Node, ids: Array[String], at: Vector3, drop_weapon: Callable) -> void:
	for id in ids:
		var spot: Vector3 = DROP_TABLE.free_spot(world, at)
		var weapon := CONFIG.weapon_index(id)
		if weapon >= 0:
			if drop_weapon.is_valid():
				drop_weapon.call(weapon, spot)
			continue
		if not SCENES.has(id):
			continue
		var item: Node3D = (SCENES[id] as PackedScene).instantiate()
		world.add_child(item)
		item.global_position = spot
		item.call("settle_on_floor")
		# Authored loot stays until collected; enemy drops fade (drop_table.gd).
		item.set_meta(&"persistent_loot", true)
		item.add_to_group(DROP_TABLE.DROP_GROUP)
