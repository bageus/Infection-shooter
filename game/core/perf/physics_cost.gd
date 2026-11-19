extends RefCounted
## Adds up the time that per-frame physics scripts take, in total and per script, so the F3 frame log can split a physics step into scripts and engine.
class_name PhysicsCost

static var usec := 0
static var by_script: Dictionary = {}
static var wakes: Dictionary = {}


static func add(script: StringName, spent: int) -> void:
	usec += spent
	by_script[script] = int(by_script.get(script, 0)) + spent


## Records the time since `since` under `script` and returns now, so consecutive steps can be timed in one chain.
static func lap(script: StringName, since: int) -> int:
	var now := Time.get_ticks_usec()
	add(script, now - since)
	return now


## Counts a request to wake `body`, keyed by its model or node name and the code path, so the F3 log shows what wakes debris.
static func woke(body: Node, reason: StringName) -> void:
	var kind := String(body.name)
	var model = body.get("model_path")
	if model is String and not model.is_empty():
		kind = model.get_file().get_basename()
	var key := "%s:%s" % [kind, reason]
	wakes[key] = int(wakes.get(key, 0)) + 1


# The three most frequent wake requests so far as "kind:reason=count,...".
static func top_wakes() -> String:
	var keys := wakes.keys()
	keys.sort_custom(func(a, b) -> bool: return wakes[a] > wakes[b])
	return ",".join(keys.slice(0, 3).map(func(key) -> String: return "%s=%d" % [key, wakes[key]]))
