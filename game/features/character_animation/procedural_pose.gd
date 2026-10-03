extends RefCounted
## Pure pose maths for the procedural animation backend of the shared
## character driver. A pose is expressed in the animated visual's local space
## (front is +Z, up is +Y) and rotates around the visual's feet.
## Presentation only: no gameplay state and no scene access.

const STRIDE_STEPS_PER_SECOND := 2.2

# Locomotion tuning (all values are per visual, set from the driver exports).
var bob_height := 0.06
var sway_degrees := 4.0
var lean_degrees := 8.0
var stride_hz := STRIDE_STEPS_PER_SECOND
var attack_duration := 0.55
var attack_lunge := 0.28
var death_duration := 1.2
var death_pitch_degrees := -88.0
var feet := Vector3.ZERO


func locomotion(speed_ratio: float, phase: float, time: float) -> Transform3D:
	var ratio := clampf(speed_ratio, 0.0, 1.4)
	var step := sin(phase * PI)
	var breath := sin(time * 1.7) * 0.012 * (1.0 - minf(ratio, 1.0))
	var lean := deg_to_rad(lean_degrees) * minf(ratio, 1.0)
	var sway := step * deg_to_rad(sway_degrees) * ratio
	var rotation := Basis(Vector3.RIGHT, lean) * Basis(Vector3.FORWARD, sway)
	var pose := _about_feet(rotation)
	pose.origin.y += absf(step) * bob_height * ratio
	pose.basis = pose.basis * Basis.from_scale(Vector3(1.0, 1.0 + breath, 1.0))
	return pose


# progress is 0..1 over attack_duration: wind-up, strike, recovery.
func attack(progress: float) -> Transform3D:
	var t := clampf(progress, 0.0, 1.0)
	var pitch := 0.0
	var forward := 0.0
	var squash := 0.0
	if t < 0.35:
		var k := _ease(t / 0.35)
		pitch = -12.0 * k
		forward = -0.08 * k
	elif t < 0.55:
		var k := _ease((t - 0.35) / 0.2)
		pitch = lerpf(-12.0, 22.0, k)
		forward = lerpf(-0.08, attack_lunge, k)
		squash = 0.04 * k
	else:
		var k := _ease((t - 0.55) / 0.45)
		pitch = lerpf(22.0, 0.0, k)
		forward = lerpf(attack_lunge, 0.0, k)
		squash = 0.04 * (1.0 - k)
	var pose := _about_feet(Basis(Vector3.RIGHT, deg_to_rad(pitch)))
	pose.origin.z += forward
	pose.basis = pose.basis * Basis.from_scale(Vector3(1.0 + squash * 0.5, 1.0 - squash, 1.0 + squash * 0.5))
	return pose


# Topples backwards around the feet and settles slightly into the floor.
func death(progress: float) -> Transform3D:
	var t := clampf(progress, 0.0, 1.0)
	var fall := t * t * (3.0 - 2.0 * t)
	var settle := clampf((t - 0.8) / 0.2, 0.0, 1.0)
	var pitch := deg_to_rad(death_pitch_degrees) * fall
	var pose := _about_feet(Basis(Vector3.RIGHT, pitch))
	pose.origin.y -= 0.06 * settle
	return pose


# Short additive flinch; elapsed in seconds over duration.
func flinch(elapsed: float, duration: float) -> Transform3D:
	var t := clampf(elapsed / maxf(duration, 0.001), 0.0, 1.0)
	var pulse := sin(t * PI)
	var pose := _about_feet(Basis(Vector3.RIGHT, deg_to_rad(-9.0) * pulse))
	pose.origin.z -= 0.05 * pulse
	pose.basis = pose.basis * Basis.from_scale(Vector3(1.0, 1.0 - 0.03 * pulse, 1.0))
	return pose


func _about_feet(rotation: Basis) -> Transform3D:
	return Transform3D(rotation, feet - rotation * feet)


static func _ease(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)
