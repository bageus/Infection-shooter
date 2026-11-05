extends RefCounted
## Optional effects (decals, debris, blood marks) stop being added while free memory is nearly gone:
## once an allocation fails the engine only prints errors, and the effect is lost anyway.

const LOW_BYTES := 200 * 1024 * 1024
const CHECK_MSEC := 500
static var _last_check := -CHECK_MSEC
static var _low := false
## Tests set the free memory (bytes) instead of asking the system; -2 asks the system.
static var available_override := -2


## True while less than LOW_BYTES of memory is free. Unknown free memory (-1, e.g. in a browser) is never low.
## The system is asked at most every CHECK_MSEC; pass fresh = true to ask now.
static func low(fresh: bool = false) -> bool:
	var now := Time.get_ticks_msec()
	if fresh or now - _last_check >= CHECK_MSEC:
		_last_check = now
		var available := available_override if available_override != -2 else int(OS.get_memory_info().get("available", -1))
		_low = available >= 0 and available < LOW_BYTES
	return _low
