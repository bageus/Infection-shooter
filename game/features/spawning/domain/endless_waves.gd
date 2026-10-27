extends RefCounted
## Endless mode: every round replays the authored queues, a little harder each time.
## Pure data; the wave director starts a round when the previous one is cleared.

const SPAWN_CONFIG := preload("res://game/features/spawning/public/spawn_config.gd")
const COUNT_GROWTH := 0.2
const INTERVAL_DECAY := 0.95
const INTERVAL_FLOOR := 0.3
## Added to health and damage percents per round; the config caps them at STAT_MAX.
const STAT_STEP := 5.0
## [first round, kind]: heavier infected join the first queue from that round on.
const UNLOCKS: Array = [[4, "brute"], [8, "titan"], [12, "colossus"]]


## `queue` as it plays in round `round_number` (1 is the authored queue).
static func queue_for_round(queue: Dictionary, round_number: int) -> Dictionary:
	var config := SPAWN_CONFIG.sanitize_queue(queue)
	var grown := maxi(round_number - 1, 0)
	for entry: Dictionary in config["enemies"]:
		entry["count"] = clampi(roundi(int(entry["count"]) * (1.0 + COUNT_GROWTH * grown)), 1, SPAWN_CONFIG.COUNT_MAX)
	config["interval"] = maxf(float(config["interval"]) * pow(INTERVAL_DECAY, grown), minf(float(config["interval"]), INTERVAL_FLOOR))
	for key: String in ["health", "damage"]:
		config[key] = minf(float(config[key]) + STAT_STEP * grown, SPAWN_CONFIG.STAT_MAX)
	config["start"] = "trigger"
	return config


## Like queue_for_round, plus the heavier kinds unlocked by `round_number` (first queue of a point only).
static func first_queue_for_round(queue: Dictionary, round_number: int) -> Dictionary:
	var config := queue_for_round(queue, round_number)
	for unlock: Array in UNLOCKS:
		if round_number < int(unlock[0]) or config["enemies"].size() >= SPAWN_CONFIG.ENTRIES_MAX:
			continue
		config["enemies"].append({"enemy": unlock[1], "count": 1 + (round_number - int(unlock[0])) / 2})
	return config
