extends RefCounted
## Adds up the time that per-frame physics scripts take, in total and per script, so the F3 frame log can split a physics step into scripts and engine.
class_name PhysicsCost

static var usec := 0
static var by_script: Dictionary = {}


static func add(script: StringName, spent: int) -> void:
	usec += spent
	by_script[script] = int(by_script.get(script, 0)) + spent
