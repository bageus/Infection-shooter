extends RefCounted
## Scope visibility of the held weapon: RMB hides or shows the scope, and a shot
## fired while the scope is hidden waits until the scope has been raised.

const RAISE_TIME := 0.2

var hidden := false
var _raise_remaining := 0.0
var _shot_pending := false


func reset() -> void:
	hidden = false
	_raise_remaining = 0.0
	_shot_pending = false


func toggle(has_scope: bool) -> void:
	if not has_scope:
		return
	hidden = not hidden
	_raise_remaining = 0.0
	_shot_pending = false


# Returns true when a shot should be fired on this physics tick.
func step(delta: float, has_scope: bool, fire_pressed: bool) -> bool:
	if _raise_remaining > 0.0:
		_raise_remaining = maxf(0.0, _raise_remaining - delta)
		if _raise_remaining == 0.0 and _shot_pending:
			_shot_pending = false
			return true
		return false
	if not fire_pressed:
		return false
	if has_scope and hidden:
		hidden = false
		_shot_pending = true
		_raise_remaining = RAISE_TIME
		return false
	return true
