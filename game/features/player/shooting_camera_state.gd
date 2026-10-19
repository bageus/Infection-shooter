extends RefCounted
## Player-local shot envelope. Distance smoothing stays with the camera owner.
const MAX_OFFSET := 0.06
const MAX_KICK := 0.1
const HOLD_SECONDS := 0.05
const RECOVERY_PER_SECOND := 0.25
const IMPULSES := {
	"PISTOL": 0.01, "UZI": 0.01, "RIFLE": 0.015,
	"AK": 0.015, "M4": 0.013, "SHOTGUN": 0.024,
	"SNIPER RIFLE": 0.03, "MINIGUN": 0.016, "GRENADE LAUNCHER": 0.036
}
var offset := 0.0
var _hold := 0.0


func shot(weapon: String) -> void:
	offset = minf(MAX_OFFSET, offset + float(IMPULSES.get(weapon, 0.005)))
	_hold = HOLD_SECONDS


## A skill impact: pulls the camera out a little, then it settles back.
func kick(amount: float) -> void:
	offset = minf(MAX_KICK, offset + amount)
	_hold = HOLD_SECONDS


func tick(delta: float) -> float:
	var recovery_time := maxf(0.0, delta - _hold)
	_hold = maxf(0.0, _hold - delta)
	offset = move_toward(offset, 0.0, recovery_time * RECOVERY_PER_SECOND)
	return offset
