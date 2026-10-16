extends RefCounted
## Player-local shot envelope. Distance smoothing stays with the camera owner.
const MAX_OFFSET := 0.03
const HOLD_SECONDS := 0.3
const RECOVERY_PER_SECOND := 0.012
const IMPULSES := {
	"PISTOL": 0.005, "UZI": 0.005, "RIFLE": 0.0075,
	"AK": 0.0075, "M4": 0.0065, "SHOTGUN": 0.012,
	"SNIPER RIFLE": 0.015, "MINIGUN": 0.008, "GRENADE LAUNCHER": 0.018
}
var offset := 0.0
var _hold := 0.0


func shot(weapon: String) -> void:
	offset = minf(MAX_OFFSET, offset + float(IMPULSES.get(weapon, 0.005)))
	_hold = HOLD_SECONDS


func tick(delta: float) -> float:
	var recovery_time := maxf(0.0, delta - _hold)
	_hold = maxf(0.0, _hold - delta)
	offset = move_toward(offset, 0.0, recovery_time * RECOVERY_PER_SECOND)
	return offset
