extends RefCounted
## Remaining physical displacement, consumed even if a wall blocks the step.
const RECOVERY_SECONDS := 0.045
const MAX_PENDING := 0.08
const DISTANCES := {
	"PISTOL": 0.005, "UZI": 0.005, "AK": 0.01, "M4": 0.008,
	"SHOTGUN": 0.02, "SNIPER RIFLE": 0.025, "MINIGUN": 0.007,
	"GRENADE LAUNCHER": 0.025
}
var remaining := Vector3.ZERO


func shot(weapon: String, forward: Vector3) -> void:
	forward.y = 0.0
	if forward.is_zero_approx():
		return
	remaining = (remaining - forward.normalized() * float(DISTANCES.get(weapon, 0.005))).limit_length(MAX_PENDING)


func step(delta: float) -> Vector3:
	var motion := remaining * (1.0 - exp(-maxf(delta, 0.0) / RECOVERY_SECONDS))
	remaining -= motion
	if remaining.length_squared() < 0.0000000001:
		motion += remaining
		remaining = Vector3.ZERO
	return motion
