extends RefCounted
## Remaining physical displacement, consumed even if a wall blocks the step.
const RECOVERY_SECONDS := 0.045
const MAX_PENDING := 0.08
const DISTANCES := {
	"PISTOL": 0.005, "UZI": 0.005, "AK": 0.01, "M4": 0.008,
	"SHOTGUN": 0.02, "SNIPER RIFLE": 0.025, "MINIGUN": 0.007,
	"GRENADE LAUNCHER": 0.025
}
## Visual kick (muzzle rise, torso jolt) and camera trauma added per shot, by weapon weight.
const KICK_DECAY_SECONDS := 0.08
const TRAUMA_DECAY_PER_SECOND := 4.0
const SHAKE_METRES := 0.05
const WEIGHTS := {
	"PISTOL": 0.5, "UZI": 0.35, "AK": 0.45, "M4": 0.4,
	"SHOTGUN": 1.0, "SNIPER RIFLE": 1.0, "MINIGUN": 0.25,
	"GRENADE LAUNCHER": 1.0
}
var remaining := Vector3.ZERO
## 0..1 envelope of the weapon/torso kick, decays in step().
var kick := 0.0
var shake_enabled := true
var _trauma := 0.0


func shot(weapon: String, forward: Vector3) -> void:
	var weight := float(WEIGHTS.get(weapon, 0.4))
	kick = minf(1.0, kick + weight)
	_trauma = minf(1.0, _trauma + weight * 0.6)
	forward.y = 0.0
	if forward.is_zero_approx():
		return
	remaining = (remaining - forward.normalized() * float(DISTANCES.get(weapon, 0.005))).limit_length(MAX_PENDING)


func step(delta: float) -> Vector3:
	kick *= exp(-maxf(delta, 0.0) / KICK_DECAY_SECONDS)
	if kick < 0.001:
		kick = 0.0
	var motion := remaining * (1.0 - exp(-maxf(delta, 0.0) / RECOVERY_SECONDS))
	remaining -= motion
	if remaining.length_squared() < 0.0000000001:
		motion += remaining
		remaining = Vector3.ZERO
	return motion


## Camera-rig offset for this frame; zero when shake is off.
func camera_shake(delta: float) -> Vector3:
	_trauma = maxf(0.0, _trauma - TRAUMA_DECAY_PER_SECOND * maxf(delta, 0.0))
	if not shake_enabled or _trauma <= 0.0:
		return Vector3.ZERO
	var power := _trauma * _trauma * SHAKE_METRES
	return Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * power
