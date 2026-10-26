extends RefCounted
## Authored waves of one spawn point: plain data, no scenes or physics.
## {"queues": [queue, ...]}; queues run independently and each one fires once.
## queue: {"enemies": [{"enemy": id, "count": int}, ...], "interval": float, "rule": id, "batch": int,
##  "start": id, "trigger": id, "delay": float, "health": float, "damage": float}
## (health and damage are percents of the enemy's base values). The first queue always starts by
## trigger. A flat legacy config {"enemy", "count", ...} is read as a single queue.

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
## How a queue after the first one starts: `time` seconds after the previous queue
## started, or by the death of the infected linked to it (`trigger`).
const STARTS: Array[String] = ["time", "trigger"]
const START_LABELS: Array[String] = ["Через время после предыдущей", "По триггеру"]
const QUEUES_MAX := 8
const ENTRIES_MAX := 6
const DELAY_MAX := 600.0
const COUNT_MAX := 200
const BATCH_MAX := 30
const INTERVAL_MIN := 0.1
const INTERVAL_MAX := 60.0
const STAT_MIN := 50.0
const STAT_MAX := 200.0


static func defaults() -> Dictionary:
	return {"queues": [default_queue()]}


static func default_queue() -> Dictionary:
	return {
		"enemies": [{"enemy": "hunger", "count": 20}], "interval": 1.0, "rule": "stream", "batch": 5,
		"start": "trigger", "trigger": "any", "delay": 10.0, "health": 100.0, "damage": 100.0,
	}


## Always returns a usable config; unknown ids and out-of-range numbers are repaired.
static func sanitize(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return defaults()
	var source: Dictionary = raw
	var queues: Array[Dictionary] = []
	if source.get("queues") is Array:
		for entry: Variant in source["queues"]:
			if queues.size() < QUEUES_MAX:
				queues.append(sanitize_queue(entry))
	if queues.is_empty():
		queues.append(sanitize_queue(source))
	queues[0]["start"] = "trigger"
	return {"queues": queues}


static func sanitize_queue(raw: Variant) -> Dictionary:
	var config := default_queue()
	if not raw is Dictionary:
		return config
	var source: Dictionary = raw
	for key: String in ["rule", "trigger", "start"]:
		var allowed: Array[String] = RULES if key == "rule" else (TRIGGERS if key == "trigger" else STARTS)
		if str(source.get(key, "")) in allowed:
			config[key] = str(source[key])
	if _number(source.get("batch")):
		config["batch"] = clampi(int(source["batch"]), 1, BATCH_MAX)
	if _number(source.get("interval")):
		config["interval"] = clampf(float(source["interval"]), INTERVAL_MIN, INTERVAL_MAX)
	if _number(source.get("delay")):
		config["delay"] = clampf(float(source["delay"]), 0.0, DELAY_MAX)
	for key: String in ["health", "damage"]:
		if _number(source.get(key)):
			config[key] = clampf(float(source[key]), STAT_MIN, STAT_MAX)
	var entries: Array[Dictionary] = []
	if source.get("enemies") is Array:
		for entry: Variant in source["enemies"]:
			if entries.size() < ENTRIES_MAX and entry is Dictionary:
				entries.append(_entry(entry))
	elif source.has("enemy") or source.has("count"):
		entries.append(_entry(source))
	if not entries.is_empty():
		config["enemies"] = entries
	return config


static func _entry(source: Dictionary) -> Dictionary:
	var id := str(source.get("enemy", ""))
	var count: Variant = source.get("count")
	return {"enemy": id if id in ENEMIES else "hunger", "count": clampi(int(count), 1, COUNT_MAX) if _number(count) else 20}


## Infected a queue spawns in total.
static func total_count(queue: Dictionary) -> int:
	var total := 0
	for entry: Dictionary in queue["enemies"]:
		total += int(entry["count"])
	return total


## Id that links a placed infected to one queue of a point: the bare point id for the
## first queue (as before queues existed), "<id>#<n>" for the others.
static func link_key(point_id: String, queue_index: int) -> String:
	return point_id if queue_index <= 0 else "%s#%d" % [point_id, queue_index]


## Inverse of link_key: [point_id, queue_index].
static func split_link(key: String) -> Array:
	var cut := key.rfind("#")
	if cut > 0 and key.substr(cut + 1).is_valid_int():
		return [key.substr(0, cut), int(key.substr(cut + 1))]
	return [key, 0]


static func scene_path(enemy_id: String) -> String:
	return str(ENEMY_SCENES.get(enemy_id, ENEMY_SCENES["hunger"]))


static func enemy_label(enemy_id: String) -> String:
	return ENEMY_LABELS[maxi(ENEMIES.find(enemy_id), 0)]


## One line for lists and the planner marker: "Hunger ×20 + Brute ×3 · 2 оч.".
static func summary(config: Dictionary) -> String:
	var queues: Array = sanitize(config)["queues"]
	return queue_summary(queues[0]) + (" · %d оч." % queues.size() if queues.size() > 1 else "")


static func queue_summary(queue: Dictionary) -> String:
	var parts: Array[String] = []
	for entry: Dictionary in queue["enemies"]:
		parts.append("%s ×%d" % [enemy_label(str(entry["enemy"])), int(entry["count"])])
	return " + ".join(parts)


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
