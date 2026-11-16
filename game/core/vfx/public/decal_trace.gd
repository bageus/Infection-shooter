extends RefCounted
## Temporary in-game trace for wall decals and glass hitches; set ON to false to silence it.
const ON := true


static func drop(message: String) -> void:
	if ON:
		print("[decal-trace] " + message)


static func timed(label: String, started_usec: int, budget_ms: float) -> void:
	var ms := (Time.get_ticks_usec() - started_usec) / 1000.0
	if ON and ms > budget_ms:
		print("[hitch-trace] %s took %.1f ms" % [label, ms])
