extends RefCounted
## Enemy speed tuning (settings: enemy_move_speed_multiplier, enemy_animation_multiplier).
## Multiplies the authored movement speed and locomotion animation pace of every infected; 1.0 keeps them.

const MIN_MULTIPLIER := 0.5
const MAX_MULTIPLIER := 2.0

## Set from the player's settings. Read live, so enemies already on the map follow a change.
static var move_multiplier := 1.0
static var animation_multiplier := 1.0


static func clamp_multiplier(value: float) -> float:
	return clampf(value, MIN_MULTIPLIER, MAX_MULTIPLIER) if is_finite(value) else 1.0


## Scales the driver's authored locomotion pace; the authored value is recorded on the first call.
static func drive_locomotion(driver: Node) -> void:
	if driver == null:
		return
	if not driver.has_meta(&"authored_locomotion_speed"):
		driver.set_meta(&"authored_locomotion_speed", driver.get("locomotion_speed_multiplier"))
	driver.set("locomotion_speed_multiplier", float(driver.get_meta(&"authored_locomotion_speed")) * animation_multiplier)


## Re-scales the pace of every infected still alive, so a settings change reaches enemies already on the map.
static func drive_live_enemies(tree: SceneTree) -> void:
	for enemy in tree.get_nodes_in_group("infected_alive"):
		drive_locomotion(enemy.get_node_or_null("AnimationDriver"))
