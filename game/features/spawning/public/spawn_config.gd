extends RefCounted
## Authored wave of one spawn point: plain data, no scenes or physics.
## {"enemy": id, "count": int, "interval": float, "rule": id, "batch": int, "trigger": id}

## Enemy kinds a point can spawn, in palette order.
const ENEMIES: Array[String] = ["hunger", "revenant", "brute", "titan", "colossus", "horde"]
const ENEMY_LABELS: Array[String] = ["Hunger", "Revenant", "Brute", "Titan", "Colossus", "Horde"]
const ENEMY_SCENES := {
	"hunger": "res://game/features/infected/public/infected_hunger.tscn",
	"revenant": "res://game/features/infected/public/infected_revenant.tscn",
	"brute": "res://game/features/infected/public/infected_brute.tscn",
	"titan": "res://game/features/infected/public/infected_titan.tscn",
	"colossus": "res://game/features/infected/public/infected_colossus.tscn",
	"horde": "res://game/features/infected/public/infected_horde.tscn",
}
## stream: one per interval; burst: a batch per interval; refill: one per
## interval while fewer than `batch` of this point's infected are alive.
const RULES: Array[String] = ["stream", "burst", "refill"]
const RULE_LABELS: Array[String] = ["Поток: по одному", "Пачками", "Подпитка: держать рядом"]
## any: the first death among the linked infected starts the wave; all: the last one.
const TRIGGERS: Array[String] = ["any", "all"]
const TRIGGER_LABELS: Array[String] = ["Любой из связанных", "Все связанные"]
const COUNT_MAX := 200
const BATCH_MAX := 30
const INTERVAL_MIN := 0.1
const INTERVAL_MAX := 60.0


static func defaults() -> Dictionary:
	return {"enemy": "hunger", "count": 20, "interval": 1.0, "rule": "stream", "batch": 5, "trigger": "any"}


## Always returns a usable config; unknown ids and out-of-range numbers are repaired.
static func sanitize(raw: Variant) -> Dictionary:
	var config := defaults()
	if not raw is Dictionary:
		return config
	var source: Dictionary = raw
	for key: String in ["enemy", "rule", "trigger"]:
		var allowed: Array[String] = ENEMIES if key == "enemy" else (RULES if key == "rule" else TRIGGERS)
		if str(source.get(key, "")) in allowed:
			config[key] = str(source[key])
	if _number(source.get("count")):
		config["count"] = clampi(int(source["count"]), 1, COUNT_MAX)
	if _number(source.get("batch")):
		config["batch"] = clampi(int(source["batch"]), 1, BATCH_MAX)
	if _number(source.get("interval")):
		config["interval"] = clampf(float(source["interval"]), INTERVAL_MIN, INTERVAL_MAX)
	return config


static func scene_path(enemy_id: String) -> String:
	return str(ENEMY_SCENES.get(enemy_id, ENEMY_SCENES["hunger"]))


static func enemy_label(enemy_id: String) -> String:
	return ENEMY_LABELS[maxi(ENEMIES.find(enemy_id), 0)]


## One line for lists and the planner marker: "Hunger ×20".
static func summary(config: Dictionary) -> String:
	var clean := sanitize(config)
	return "%s ×%d" % [enemy_label(str(clean["enemy"])), int(clean["count"])]


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
