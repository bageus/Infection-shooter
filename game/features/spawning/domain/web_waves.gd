extends RefCounted
## Web arena waves of one spawn hole: the queue of wave N from the hole's first queue and its
## "web" settings (spawn_config.sanitize_web). Pure data; wave 0 (the placed infected) has no queue.

const SPAWN_CONFIG := preload("res://game/features/spawning/public/spawn_config.gd")


static func is_boss(config: Dictionary) -> bool:
	return config.has("web") and str(config["web"]["role"]) == "boss"


## True when the hole spawns something in `wave` (1 is the first wave). Boss holes only in their wave.
static func spawns_in_wave(config: Dictionary, wave: int) -> bool:
	if not config.has("web") or wave < 1:
		return false
	return wave == int(config["web"]["boss_wave"]) if is_boss(config) else true


## Queue the hole plays in `wave`; the boss hole plays one Horde.
static func queue_for_wave(config: Dictionary, wave: int) -> Dictionary:
	var clean := SPAWN_CONFIG.sanitize(config)
	var web: Dictionary = clean["web"] if clean.has("web") else SPAWN_CONFIG.default_web()
	var queue: Dictionary = clean["queues"][0]
	queue["start"] = "trigger"
	if str(web["role"]) == "boss":
		queue["enemies"] = [{"enemy": "horde", "count": 1}]
		return queue
	var grown := maxi(wave - 1, 0)
	var base_total := maxi(SPAWN_CONFIG.total_count(queue), 1)
	var total := clampi(base_total + int(web["add"]) * grown, int(web["min"]), int(web["max"]))
	var entries: Array = queue["enemies"]
	var left := total
	for index in range(entries.size() - 1, 0, -1):
		entries[index]["count"] = clampi(roundi(float(entries[index]["count"]) * total / base_total), 0, left)
		left -= int(entries[index]["count"])
	entries[0]["count"] = left
	for unlock: Dictionary in web["unlocks"]:
		if wave >= int(unlock["from_wave"]):
			_replace_first(entries, unlock, total, wave)
	queue["enemies"] = entries.filter(func(entry: Dictionary) -> bool: return int(entry["count"]) > 0)
	for key: String in ["health", "damage"]:
		queue[key] = minf(float(queue[key]) + float(web[key + "_step"]) * grown, SPAWN_CONFIG.STAT_MAX)
	return queue


## The new kind takes `share`% of the wave at its first wave, `step` more each wave, at most `cap`,
## all from the first kind of the queue (which never goes below zero).
static func _replace_first(entries: Array, unlock: Dictionary, total: int, wave: int) -> void:
	var kind := str(unlock["enemy"])
	if str(entries[0]["enemy"]) == kind:
		return
	var wanted := roundi(total * float(unlock["share"]) / 100.0) + int(unlock["step"]) * (wave - int(unlock["from_wave"]))
	var moved := mini(mini(wanted, int(unlock["cap"])), int(entries[0]["count"]))
	if moved <= 0:
		return
	for entry: Dictionary in entries:
		if str(entry["enemy"]) == kind:
			entry["count"] = int(entry["count"]) + moved
			entries[0]["count"] = int(entries[0]["count"]) - moved
			return
	if entries.size() < SPAWN_CONFIG.ENTRIES_MAX:
		entries.append({"enemy": kind, "count": moved})
		entries[0]["count"] = int(entries[0]["count"]) - moved
