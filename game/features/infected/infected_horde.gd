extends "res://game/features/infected/infected_capsule.gd"
## Horde: crawls toward the player, then braces and rams at high speed; it
## has no swipe. From time to time it pulses and calls infected to its side
## (ADR-0016). Summoned infected are ordinary scenes wired like their caller.

const SHOCKWAVE := preload("res://game/features/infected/ground_shockwave.gd")
const SUMMON_PEAK := 0.45
const SUMMON_RULE := preload("res://game/features/infected/domain/horde_summon.gd")

enum State { CRAWL, BRACE, RAM, RECOVER, SUMMON }

@export var crawl_speed := 2.4
@export var ram_trigger_distance := 8.0
@export var ram_speed := 8.6
@export var ram_brace_seconds := 0.4
@export var ram_max_seconds := 1.4
@export var ram_recover_seconds := 0.9
@export var ram_cooldown := 3.0
@export var ram_hit_radius := 2.3
@export var ram_steer := 1.4
@export var summon_scene: PackedScene
@export var summon_revenant_scene: PackedScene
@export var summon_brute_scene: PackedScene
@export var summon_interval := 12.0
@export var summon_range := 24.0
@export var summon_count := 3
@export var summon_spawn_radius := 3.6

var state: State = State.CRAWL
var _state_time := 0.0
var _ram_direction := Vector3.FORWARD
var _ram_cooldown := 1.5
var _ram_struck := false
var _summon_cooldown := 5.0
var _summon_pending := -1.0
var _summon_busy_until := 0.0


func _behaviour_tick(delta: float, target_offset: Vector3) -> void:
	_state_time += delta
	_ram_cooldown = maxf(0.0, _ram_cooldown - delta)
	_summon_cooldown = maxf(0.0, _summon_cooldown - delta)
	var distance := target_offset.length()
	match state:
		State.CRAWL:
			if _blast_stun_remaining > 0.0:
				return
			if _summon_cooldown <= 0.0 and distance <= summon_range and distance > ram_hit_radius * 2.0:
				_start_summon()
			elif _ram_cooldown <= 0.0 and distance <= ram_trigger_distance and can_ram():
				_enter(State.BRACE)
				audio.growl(2.0)
				_ram_direction = target_offset.normalized() if distance > 0.01 else -global_transform.basis.z
		State.BRACE:
			_cached_desired = Vector3.ZERO
			if distance > 0.01:
				_ram_direction = target_offset.normalized()
				_face_direction = _ram_direction
			if _state_time >= ram_brace_seconds:
				_enter(State.RAM)
				_ram_struck = false
		State.RAM:
			_tick_ram(delta, target_offset)
		State.RECOVER:
			_cached_desired = _cached_desired.move_toward(Vector3.ZERO, ram_speed * 2.0 * delta)
			if _state_time >= ram_recover_seconds:
				_ram_cooldown = ram_cooldown
				_enter(State.CRAWL)
		State.SUMMON:
			_cached_desired = Vector3.ZERO
			if _summon_pending >= 0.0:
				_summon_pending -= delta
				if _summon_pending < 0.0:
					_release_summon()
			if _summon_pending < 0.0 and not _animation_busy():
				_enter(State.CRAWL)


func _tick_ram(delta: float, target_offset: Vector3) -> void:
	if _blast_stun_remaining > 0.0:
		_enter(State.RECOVER)
		return
	if target_offset.length() > 0.01:
		var wanted := target_offset.normalized()
		var angle := _ram_direction.signed_angle_to(wanted, Vector3.UP)
		_ram_direction = _ram_direction.rotated(Vector3.UP, clampf(angle, -ram_steer * delta, ram_steer * delta))
	_face_direction = _ram_direction
	var speed := lerpf(crawl_speed, ram_speed, clampf(_state_time / 0.3, 0.0, 1.0)) * _mobility
	_cached_desired = _ram_direction * speed
	if not _ram_struck and target_offset.length() <= ram_hit_radius:
		_ram_struck = true
		if is_instance_valid(_target) and _target.has_method("take_damage"):
			_target.call("take_damage", attack_damage)
			audio.call("play", &"horde_ram_hit")
		_enter(State.RECOVER)
		return
	if _state_time >= ram_max_seconds or (_state_time > 0.25 and is_on_wall()):
		_enter(State.RECOVER)


# Each lost tentacle slows the Horde; with few left it can no longer ram.
func _part_lost(part: StringName) -> void:
	if String(part).begins_with("tentacle"):
		_mobility = 0.35 + 0.65 * float(_parts.remaining("tentacle")) / 8.0
		return
	super._part_lost(part)


func can_ram() -> bool:
	return _parts == null or int(_parts.remaining("tentacle")) > 3


# The Horde has no swipe: it only hurts by ramming.
func _try_attack() -> void:
	pass


func _desired_velocity_from_offset(offset: Vector3) -> Vector3:
	if state != State.CRAWL:
		return _cached_desired
	var distance := offset.length()
	if distance <= 0.0001:
		return Vector3.ZERO
	_face_direction = offset / distance
	if distance <= ram_hit_radius:
		return Vector3.ZERO
	return _face_direction * crawl_speed * _mobility


func _start_summon() -> void:
	_enter(State.SUMMON)
	_summon_cooldown = summon_interval
	var duration := _play_animation(&"summon")
	audio.call("play", &"horde_summon")
	_summon_pending = duration * SUMMON_PEAK if duration > 0.0 else 0.0
	_summon_busy_until = duration


func _animation_busy() -> bool:
	return _state_time < _summon_busy_until


func _release_summon() -> void:
	_summon_pending = -1.0
	if _dead or health <= 0.0 or get_parent() == null:
		return
	var parent: Node = effects_root if is_instance_valid(effects_root) else get_parent()
	var pulse := SHOCKWAVE.new()
	pulse.name = "SummonPulse"
	parent.add_child(pulse)
	pulse.configure(global_position + Vector3(0.0, -_half_height(), 0.0), 7.0, 11.0, 0.0, 0.0, self, Color(0.78, 0.22, 0.3, 0.7))
	var scene := _summon_scene_for_health()
	if scene == null:
		return
	# No alive-count gate: every cooldown may add another full wave.
	for index in summon_count:
		var enemy := scene.instantiate() as CharacterBody3D
		var shape := (enemy.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
		var spot := _spawn_point(index, summon_count, shape.radius, shape.height * 0.5)
		if spot == Vector3.INF:
			enemy.free()
			continue
		# Place before entering the tree to avoid overlap at the origin.
		var parent_node := get_parent() as Node3D
		enemy.position = parent_node.global_transform.affine_inverse() * spot if parent_node != null else spot
		enemy.set_meta("summoned_by", get_instance_id())
		get_parent().add_child(enemy)
		if enemy.has_method("configure_world"):
			enemy.call("configure_world", effects_root, impact_pool)
		if enemy.has_method("set_target") and is_instance_valid(_target):
			enemy.call("set_target", _target)


func _summon_scene_for_health() -> PackedScene:
	match SUMMON_RULE.tier(health, max_health):
		SUMMON_RULE.Tier.BRUTE:
			return summon_brute_scene
		SUMMON_RULE.Tier.REVENANT:
			return summon_revenant_scene
	return summon_scene


# Check the selected species' entire capsule against walls and props.
func _spawn_point(index: int, total: int, radius := 0.45, half_height := 1.0) -> Vector3:
	var space := get_world_3d().direct_space_state
	var probe := CapsuleShape3D.new()
	probe.radius = radius + 0.05
	probe.height = maxf(half_height * 2.0, probe.radius * 2.0)
	var floor_y := global_position.y - _half_height()
	for attempt in 6:
		var angle := TAU * (float(index) + 0.37 * float(attempt)) / float(maxi(total, 1)) + randf_range(-0.3, 0.3)
		var point := global_position + Vector3(sin(angle), 0.0, cos(angle)) * summon_spawn_radius
		point.y = floor_y + half_height + 0.02
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = probe
		query.transform = Transform3D(Basis.IDENTITY, point)
		query.collision_mask = 1
		query.exclude = [get_rid()]
		if space.intersect_shape(query, 1).is_empty():
			return point
	return Vector3.INF


func _half_height() -> float:
	var capsule := collision_shape.shape as CapsuleShape3D
	return capsule.height * 0.5 if capsule != null else 0.6


func _enter(next: State) -> void:
	state = next
	_state_time = 0.0


func _die() -> void:
	_summon_pending = -1.0
	_enter(State.RECOVER)
	super._die()
