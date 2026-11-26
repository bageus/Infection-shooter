extends SceneTree
## Web arena waves: growth, replacement of the first kind by new kinds, boss hole.

const CONFIG := preload("res://game/features/spawning/public/spawn_config.gd")
const WEB := preload("res://game/features/spawning/domain/web_waves.gd")
var failures := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + what)


func _count(queue: Dictionary, kind: String) -> int:
	for entry: Dictionary in queue["enemies"]:
		if entry["enemy"] == kind:
			return int(entry["count"])
	return 0


func _init() -> void:
	var old := CONFIG.sanitize({"queues": [{"enemies": [{"enemy": "hunger", "count": 10}]}]})
	_check(not old.has("web") and WEB.spawns_in_wave(old, 1), "a hole without web settings plays as a wave hole")
	var web := CONFIG.default_web()
	web["unlocks"] = [{"enemy": "revenant", "from_wave": 3, "share": 5, "step": 1, "cap": 4}]
	var hole := CONFIG.sanitize({"queues": [{"enemies": [{"enemy": "hunger", "count": 10}], "health": 100, "damage": 100}], "web": web})
	_check(CONFIG.total_count(WEB.queue_for_wave(hole, 1)) == 10, "wave 1 is the authored queue")
	_check(CONFIG.total_count(WEB.queue_for_wave(hole, 3)) == 14, "growth adds 2 per wave")
	_check(CONFIG.total_count(WEB.queue_for_wave(hole, 100)) == 40, "growth stops at max")
	var third := WEB.queue_for_wave(hole, 3)
	_check(_count(third, "revenant") == 1 and _count(third, "hunger") == 13, "the new kind starts replacing at its wave")
	var fifth := WEB.queue_for_wave(hole, 5)
	_check(_count(fifth, "revenant") == 3 and CONFIG.total_count(fifth) == 18, "replacement grows by step, total kept")
	_check(_count(WEB.queue_for_wave(hole, 9), "revenant") == 4, "replacement stops at cap")
	_check(is_equal_approx(float(WEB.queue_for_wave(hole, 3)["health"]), 110.0), "health grows by percent per wave")
	_check(float(WEB.queue_for_wave(hole, 100)["health"]) == CONFIG.STAT_MAX, "health is capped")
	_check(WEB.spawns_in_wave(hole, 1) and not WEB.spawns_in_wave(hole, 0), "wave holes spawn from wave 1, not in wave 0")
	var boss := CONFIG.sanitize({"web": {"role": "boss", "boss_wave": 7}})
	_check(WEB.is_boss(boss) and WEB.spawns_in_wave(boss, 7) and not WEB.spawns_in_wave(boss, 6), "boss hole spawns only in its wave")
	var queue := WEB.queue_for_wave(boss, 7)
	_check(queue["enemies"] == [{"enemy": "horde", "count": 1}], "boss hole spawns one Horde")
	var bad := CONFIG.sanitize_web({"role": "x", "min": 9, "max": 3, "unlocks": [{"enemy": "zzz", "share": 500}]})
	_check(bad["role"] == "wave" and bad["max"] >= bad["min"] and bad["unlocks"][0]["enemy"] == "revenant" and bad["unlocks"][0]["share"] == 100.0, "bad values are repaired")
	print("web waves tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)
