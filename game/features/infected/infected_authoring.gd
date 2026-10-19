extends RefCounted
## Planner-authored options of one infected: loot and toughness/damage percentages.

const LOOT_DROP := preload("res://game/features/pickups/public/loot_drop.gd")
const LOOT_CONFIG := preload("res://game/features/pickups/public/loot_config.gd")
const ENEMY_DIFFICULTY := preload("res://game/features/infected/public/enemy_difficulty.gd")
var drop_weapon: Callable
var _owner: Node
var _base := {}


func _init(owner: Node) -> void:
	_owner = owner


func set_loot(config: Dictionary) -> void:
	_owner.set_meta(&"planning_loot", LOOT_CONFIG.sanitize(config, "auto"))


func loot() -> Dictionary:
	return LOOT_CONFIG.sanitize(_owner.get_meta(&"planning_loot") if _owner.has_meta(&"planning_loot") else null, "auto")


func stats() -> Dictionary:
	return LOOT_CONFIG.sanitize_stats(_owner.get_meta(&"planning_enemy_stats") if _owner.has_meta(&"planning_enemy_stats") else null)


## Percent of the scene's base values (50-200); safe to call before or after _ready.
func set_stats(config: Dictionary) -> void:
	if _base.is_empty():
		_base = {"health": _owner.max_health, "damage": _owner.attack_damage, "obstacle": _owner.obstacle_damage}
	var values := LOOT_CONFIG.sanitize_stats(config)
	_owner.set_meta(&"planning_enemy_stats", values)
	var ratio: float = _owner.health / _owner.max_health if _owner.max_health > 0.0 else 1.0
	_owner.max_health = float(_base["health"]) * ENEMY_DIFFICULTY.percent(float(values["health"])) / 100.0
	_owner.health = _owner.max_health * ratio
	_owner.attack_damage = float(_base["damage"]) * damage_percent() / 100.0
	_owner.obstacle_damage = float(_base["obstacle"]) * damage_percent() / 100.0


## Damage percent this infected deals after difficulty, for attacks scaled outside the stats.
func damage_percent() -> float:
	return ENEMY_DIFFICULTY.percent(float(stats()["damage"]))


## Applies stats stored on the node (map load, baked scene) once it is ready.
func apply_saved_stats() -> void:
	if _owner.has_meta(&"planning_enemy_stats") or ENEMY_DIFFICULTY.level != ENEMY_DIFFICULTY.NORMAL:
		set_stats(stats())


func release(world: Node, at: Vector3) -> void:
	LOOT_DROP.release_enemy(world, at, _owner.get_meta(&"planning_loot") if _owner.has_meta(&"planning_loot") else null, drop_weapon)
