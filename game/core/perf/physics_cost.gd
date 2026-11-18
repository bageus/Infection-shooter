extends RefCounted
## Adds up the time that per-frame physics scripts take, so the F3 frame log can split a physics step into scripts and engine.
class_name PhysicsCost

static var usec := 0
