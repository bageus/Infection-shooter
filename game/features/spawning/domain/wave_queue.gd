extends RefCounted
## Pending waves of the mission: which spawn points fired, how many infected each
## still owes and when the next one is due. Pure data; the director spawns the
## orders it returns and reports how many infected are alive.

const SPAWN_CONFIG := preload("res://game/features/spawning/public/spawn_config.gd")
## Most living infected on the level at once; waves wait for a free slot.
const MAX_ALIVE := 90

var _plans: Array[Dictionary] = []
var _fired := {}
var _cursor := 0


## True when the trigger condition holds; `dead` holds one flag per linked infected.
## A point with nothing linked never fires.
static func trigger_met(mode: String, dead: Array) -> bool:
	if dead.is_empty():
		return false
	if mode == "all":
		return not dead.has(false)
	return dead.has(true)


## Starts one queue of a point (`point_id` is its link key). Each queue fires once,
## however many triggers die later.
func activate(point_id: String, config: Dictionary) -> bool:
	if _fired.has(point_id):
		return false
	_fired[point_id] = true
	var clean := SPAWN_CONFIG.sanitize_queue(config)
	var entries: Array[Dictionary] = []
	for entry: Dictionary in clean["enemies"]:
		entries.append({"enemy": entry["enemy"], "remaining": int(entry["count"])})
	_plans.append({"id": point_id, "config": clean, "entries": entries, "remaining": SPAWN_CONFIG.total_count(clean), "cooldown": 0.0, "turn": 0})
	return true


func has_fired(point_id: String) -> bool:
	return _fired.has(point_id)


func pending(point_id: String) -> int:
	for plan in _plans:
		if plan["id"] == point_id:
			return int(plan["remaining"])
	return 0


func total_pending() -> int:
	var total := 0
	for plan in _plans:
		total += int(plan["remaining"])
	return total


func clear() -> void:
	_plans.clear()
	_fired.clear()
	_cursor = 0


## Advances every wave by `delta` and returns [{"id", "count", "enemies"}] to spawn now;
## "enemies" names the kind of each infected, taking turns between the queue's kinds.
## `alive_total` is every living infected on the level; `alive_by_point` maps a
## point id to how many of its own are alive (the "refill" rule).
func step(delta: float, alive_total: int, cap: int, alive_by_point: Dictionary) -> Array[Dictionary]:
	var orders: Array[Dictionary] = []
	var size := _plans.size()
	if size == 0:
		return orders
	var free := cap - alive_total
	var next_cursor := _cursor
	for offset in size:
		var index := (_cursor + offset) % size
		var plan: Dictionary = _plans[index]
		plan["cooldown"] = maxf(0.0, float(plan["cooldown"]) - delta)
		if float(plan["cooldown"]) > 0.0 or int(plan["remaining"]) <= 0:
			continue
		var count := mini(_wanted(plan, int(alive_by_point.get(plan["id"], 0))), free)
		if count <= 0:
			continue
		orders.append({"id": plan["id"], "count": count, "enemies": _take(plan, count)})
		plan["remaining"] = int(plan["remaining"]) - count
		plan["cooldown"] = float(plan["config"]["interval"])
		free -= count
		# The next free slot goes to the point after the one just served.
		next_cursor = index + 1
	_plans = _plans.filter(func(plan: Dictionary) -> bool: return int(plan["remaining"]) > 0)
	_cursor = next_cursor % maxi(_plans.size(), 1)
	return orders


func _take(plan: Dictionary, count: int) -> Array[String]:
	var kinds: Array[String] = []
	var entries: Array = plan["entries"]
	while kinds.size() < count:
		var entry: Dictionary = entries[int(plan["turn"]) % entries.size()]
		plan["turn"] = int(plan["turn"]) + 1
		if int(entry["remaining"]) > 0:
			entry["remaining"] = int(entry["remaining"]) - 1
			kinds.append(str(entry["enemy"]))
	return kinds


func _wanted(plan: Dictionary, alive_own: int) -> int:
	var config: Dictionary = plan["config"]
	var remaining := int(plan["remaining"])
	match str(config["rule"]):
		"burst":
			return mini(int(config["batch"]), remaining)
		"refill":
			return 1 if alive_own < int(config["batch"]) else 0
	return 1
