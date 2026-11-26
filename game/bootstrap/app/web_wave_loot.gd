extends RefCounted
## The last enemy of a web wave sometimes drops a medkit, armor or DNA where it fell (little loot on arenas).
const DROP_TABLE := preload("res://game/features/pickups/public/drop_table.gd")
const CHANCE := 0.5
const WEIGHTS := {"medkit": 0.4, "armor": 0.3, "dna": 0.3}


## Item id for two rolls in 0..1 (first: does it drop, second: which item); "" for no drop.
static func pick(drop_roll: float, item_roll: float) -> String:
	if drop_roll >= CHANCE:
		return ""
	var cursor := 0.0
	for id: String in WEIGHTS:
		cursor += float(WEIGHTS[id])
		if item_roll < cursor:
			return id
	return "medkit"


static func drop(world: Node, at: Vector3) -> void:
	var id := pick(randf(), randf())
	if id.is_empty():
		return
	var item: Node3D = DROP_TABLE.SCENES[id].instantiate()
	world.add_child(item)
	item.global_position = DROP_TABLE.free_spot(world, at)
	item.call("settle_on_floor")
	item.add_to_group(DROP_TABLE.DROP_GROUP)
	item.set_meta(&"persistent_loot", true) # stays until collected
