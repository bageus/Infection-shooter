extends RefCounted
## Spawns authored loot (see loot_config.gd) around a point on the floor.

const CONFIG := preload("res://game/features/pickups/public/loot_config.gd")
const DROP_TABLE := preload("res://game/features/pickups/public/drop_table.gd")
const SCENES := DROP_TABLE.SCENES
const BEACON := preload("res://game/features/pickups/public/pickup_beacon.gd")


## Crate loot is marked with a gold beacon so debris does not hide it.
const CRATE_BEACON_COLOR := Color(1.0, 0.82, 0.25)
const CRATE_BEACON_GLOW := 0.45
const CRATE_BEACON_ARROW_HEIGHT := 0.9
const CRATE_BEACON_ENERGY := 0.9


## Crate contents on destruction. `empty` drops nothing, `auto` rolls by crate size.
## `carried_weapons` returns the weapon slot indices the player holds; auto loot skips other weapons' ammo.
static func release_crate(world: Node, at: Vector3, config: Dictionary, size_hint: String, drop_weapon: Callable, carried_weapons: Callable = Callable(), source_id := "") -> void:
	match str(config.get("mode", "empty")):
		"manual":
			spawn(world, CONFIG.manual_list(config), at, drop_weapon, true, source_id)
		"auto":
			spawn(world, CONFIG.auto_list(size_hint, CONFIG.auto_weights(_carried(carried_weapons))), at, drop_weapon, true)


## Infected death. Without a config the classic random drop applies.
static func release_enemy(world: Node, at: Vector3, raw_config: Variant, drop_weapon: Callable, ammo_multiplier: float = 1.0, carried_weapons: Callable = Callable(), source_id := "", key_at := Vector3.INF) -> void:
	var config := CONFIG.sanitize(raw_config, "auto")
	match str(config["mode"]):
		"manual":
			spawn(world, CONFIG.manual_list(config), at, drop_weapon, false, source_id, key_at)
		"auto":
			if randf() * 100.0 >= float(config.get("chance", 100.0)):
				return
			var table := DROP_TABLE.new()
			world.add_child(table)
			table.call("drop_for_enemy", world, at, ammo_multiplier, _carried(carried_weapons))
			table.queue_free()


static func _carried(carried_weapons: Callable) -> Variant:
	return carried_weapons.call() if carried_weapons.is_valid() else null


## `source_id` is the planner id of the enemy or crate that drops the key: quests wait for that key to be picked up.
## A key lands at `key_at` (in front of the enemy) when given, so it never sits under a wide body.
static func spawn(world: Node, ids: Array[String], at: Vector3, drop_weapon: Callable, crate := false, source_id := "", key_at := Vector3.INF) -> void:
	for id in ids:
		var spot: Vector3 = DROP_TABLE.free_spot(world, key_at if id == "key" and key_at.is_finite() else at)
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
		if crate:
			item.add_child(BEACON.make(CRATE_BEACON_COLOR, CRATE_BEACON_GLOW, CRATE_BEACON_ARROW_HEIGHT, CRATE_BEACON_ENERGY))
		item.call("settle_on_floor")
		# Authored loot stays until collected; enemy drops fade (drop_table.gd).
		item.set_meta(&"persistent_loot", true)
		if id == "key" and not source_id.is_empty():
			item.set_meta(&"key_source_id", source_id)
		item.add_to_group(DROP_TABLE.DROP_GROUP)
