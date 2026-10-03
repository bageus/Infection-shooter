extends "res://game/features/infected/infected_capsule.gd"
## Colossus: besides its swipe it raises both arms and slams the floor. The
## impact sends a destructive ground wave around it (ADR-0016).

const SHOCKWAVE := preload("res://game/features/infected/ground_shockwave.gd")

@export var slam_trigger_distance := 4.2
@export var slam_cooldown := 7.0
@export_range(0.1, 0.9) var slam_hit_fraction := 0.56
@export var slam_radius := 6.0
@export var slam_wave_speed := 10.0
@export var slam_player_damage := 32.0
@export var slam_object_damage := 320.0

var _slam_cooldown := 2.5
var _slam_pending := -1.0
var _slam_busy := 0.0


func _behaviour_tick(delta: float, target_offset: Vector3) -> void:
	_slam_cooldown = maxf(0.0, _slam_cooldown - delta)
	_slam_busy = maxf(0.0, _slam_busy - delta)
	if _slam_pending >= 0.0:
		if _blast_stun_remaining > 0.0:
			_slam_pending = -1.0
		else:
			_slam_pending -= delta
			if _slam_pending < 0.0:
				_release_slam()
	if _slam_busy > 0.0:
		_cached_desired = Vector3.ZERO
		return
	if _slam_cooldown <= 0.0 and _pending_hit < 0.0 and _blast_stun_remaining <= 0.0 and target_offset.length() <= slam_trigger_distance:
		_start_slam()


func _start_slam() -> void:
	_slam_cooldown = slam_cooldown
	_attack_cooldown = maxf(_attack_cooldown, attack_interval)
	var duration := _play_animation(&"slam")
	_cached_desired = Vector3.ZERO
	if duration <= 0.0:
		_release_slam()
		return
	_slam_busy = duration
	_slam_pending = duration * slam_hit_fraction


func _release_slam() -> void:
	_slam_pending = -1.0
	var wave := SHOCKWAVE.new()
	wave.name = "SlamWave"
	var parent: Node = effects_root if is_instance_valid(effects_root) else get_parent()
	parent.add_child(wave)
	var feet := global_position + Vector3(0.0, -_half_height(), 0.0) - global_transform.basis.z * 0.9
	wave.configure(feet, slam_radius, slam_wave_speed, slam_player_damage, slam_object_damage, self, Color(0.6, 0.46, 0.34, 0.8))


# The swipe is not used while the slam animation owns the body.
func _try_attack() -> void:
	if _slam_busy > 0.0:
		return
	super._try_attack()


func _die() -> void:
	_slam_pending = -1.0
	_slam_busy = 0.0
	super._die()


func _half_height() -> float:
	var capsule := collision_shape.shape as CapsuleShape3D
	return capsule.height * 0.5 if capsule != null else 1.0
