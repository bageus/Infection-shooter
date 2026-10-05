extends CharacterBody3D

const DROP_TABLE_SCRIPT := preload("res://game/features/pickups/public/drop_table.gd")
const BODY_PARTS := preload("res://game/features/infected/body_parts.gd")
const BLOOD_FX := preload("res://game/features/infected/blood_drip_fx.gd")
const BLAST_DISMEMBER_DAMAGE := 60.0
const AUDIO := preload("res://game/features/infected/infected_audio.gd")

# Public v1 presentation facts: no effect ownership or renderer dependency.
signal projectile_blood(position: Vector3, direction: Vector3, weapon: String, excluded: Array[RID], source_id: int)
signal blood_wounded(position: Vector3, excluded: Array[RID])
signal wounded_moved(previous: Vector3, current: Vector3, excluded: Array[RID])
signal body_dragged(previous: Vector3, current: Vector3, excluded: Array[RID])
signal blood_death(position: Vector3, excluded: Array[RID], death_id: int)
# Public v1 presentation fact (ADR-0017): a body part was shot off here.
signal limb_severed(position: Vector3, direction: Vector3, excluded: Array[RID])

@export_range(0.4, 0.8) var blood_drop_distance := 0.6
@export var max_health: float = 50.0
@export var move_speed: float = 4.5
@export var attack_range: float = 1.2
@export var attack_damage: float = 15.0
@export var attack_interval: float = 1.0
@export var gravity_acceleration: float = 24.0
@export var push_decay: float = 10.0
@export var max_push_speed: float = 6.0
@export var obstacle_damage: float = 34.0
@export var obstacle_attack_interval: float = 0.45
@export var full_simulation_distance: float = 14.0
@export var sleep_distance: float = 32.0
## Fraction of the attack animation at which the blow lands.
@export_range(0.1, 0.9) var attack_hit_fraction := 0.45
## The target may step back during the wind-up by this factor of attack_range.
@export var attack_reach_tolerance := 1.35
@export var turn_speed := 14.0
## Beyond charge_distance the enemy stalks at walk_speed_factor of move_speed
## (walk clip); closer it charges at full speed (run clip). 0 always charges.
@export var charge_distance := 9.0
@export_range(0.2, 1.0) var walk_speed_factor := 0.4
## Small infected die from losing a leg; large ones limp on (ADR-0017).
@export var limb_loss_kills := true
## Scales how much damage body parts take before they come off.
@export var dismember_strength_scale := 1.0
@export var death_linger_seconds := 3.5
## Sound set (ADR-0018): footstep and voice events and their pitch.
@export var step_sound: StringName = &"step_light"
@export var growl_sound: StringName = &"growl_zombie"
@export var voice_pitch := 1.0
@export var step_pitch := 1.0
@export var death_sink_depth := 0.45

@onready var body_visual: Node3D = $Body
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var death_cloud: Area3D = $DeathCloud
@onready var _animation: Node = get_node_or_null("AnimationDriver")

var health: float
var _target: Node3D
var _attack_cooldown: float = 0.0
var _obstacle_cooldown: float = 0.0
var _dead: bool = false
var _push_velocity: Vector3 = Vector3.ZERO
var _ai_tick_offset: int = 0
var _cached_desired: Vector3 = Vector3.ZERO
var _lod_frame_offset: int = 0
var _sleeping_far := false
var _blast_stun_remaining := 0.0
var mutation_poison_remaining := 0.0
var _mutation_poison_damage := 0.0
var _blood_last_position := Vector3.ZERO
var _blood_segment_start := Vector3.ZERO
var _blood_distance := 0.0
var _pending_hit := -1.0
var _face_direction := Vector3.ZERO
var _parts: Node
var audio: AUDIO
var _mobility := 1.0
var _attack_scale := 1.0
var _last_hit_position := Vector3.ZERO
var _last_hit_direction := Vector3.ZERO

var effects_root: Node3D
var impact_pool: Node


# Public scene wiring v1; owned by the mission composition.
func configure_world(container: Node3D, impacts: Node) -> void:
	effects_root = container
	impact_pool = impacts


func _ready() -> void:
	health = max_health
	_blood_last_position = global_position
	_blood_segment_start = global_position
	_ai_tick_offset = get_instance_id() % 4
	_lod_frame_offset = get_instance_id() % 12
	death_cloud.depleted.connect(_on_death_cloud_depleted)
	_setup_body_parts()
	audio = AUDIO.new()
	audio.name = "Audio"
	add_child(audio)
	audio.setup(self, body_visual.scale.x if body_visual != null else 1.0)


func _setup_body_parts() -> void:
	var parts := BODY_PARTS.new()
	parts.name = "BodyParts"
	add_child(parts)
	var size := body_visual.scale.x if body_visual != null else 1.0
	if parts.setup(self, body_visual, max_health * dismember_strength_scale * size):
		_parts = parts
		parts.part_severed.connect(_on_part_severed)
	else:
		parts.queue_free()


func set_target(target: Node3D) -> void:
	_target = target


func apply_player_push(direction: Vector3, strength: float) -> void:
	if _dead or strength <= 0.0:
		return
	_push_velocity += direction.normalized() * strength
	if _push_velocity.length() > max_push_speed:
		_push_velocity = _push_velocity.normalized() * max_push_speed


func take_projectile_damage(
	amount: float,
	hit_position: Vector3,
	direction: Vector3,
	weapon_name: String = "PISTOL"
) -> void:
	if _dead or amount <= 0.0:
		return
	_last_hit_position = hit_position
	_last_hit_direction = direction
	var part: StringName = BODY_PARTS.TORSO
	if _parts != null:
		part = _parts.pick_part(hit_position, direction)
		_parts.wound(part, hit_position, direction, BODY_PARTS.wound_radius(weapon_name))
	projectile_blood.emit(hit_position, direction, weapon_name, _blood_exclusions(), get_instance_id())
	BLOOD_FX.spray(get_parent() as Node3D, hit_position, direction, 16, 1.0)
	audio.hit(hit_position)
	if is_instance_valid(_target) and _target.has_method("get_infection_skill"):
		if bool(_target.call("get_infection_skill", "blood_scent")) and health < max_health * 0.7:
			amount *= 1.22
	var severed := _parts != null and bool(_parts.damage_part(part, amount))
	_apply_damage(amount, false)
	# A killing shot also tears off a part that was already badly damaged.
	if _parts != null and part != BODY_PARTS.TORSO and not _parts.is_severed(part):
		if severed or (_dead and float(_parts.part_ratio(part)) <= 0.5):
			_parts.sever(part, direction)


## Explosion damage: limbs torn off fly away from the blast centre.
func take_blast_damage(amount: float, origin: Vector3) -> void:
	_last_hit_position = origin
	take_damage(amount)


func take_damage(amount: float) -> void:
	_apply_damage(amount, amount >= BLAST_DISMEMBER_DAMAGE)


func _apply_damage(amount: float, blast: bool) -> void:
	if amount <= 0.0 or _dead:
		return
	if blast and _parts != null:
		_blast_limbs(amount)
		if _dead:
			return
	var first_wound := is_equal_approx(health, max_health)
	health = maxf(0.0, health - amount)
	if first_wound:
		blood_wounded.emit(global_position, _blood_exclusions())
	# Damage over time arrives in tiny per-frame bits; only real hits flinch.
	if health > 0.0 and _animation != null and amount >= 1.0:
		_animation.call("notify_hit")
	if health <= 0.0:
		_die()


# Heavy blasts tear at one or two random limbs.
func _blast_limbs(amount: float) -> void:
	var candidates: Array[StringName] = _parts.severable_parts()
	candidates.shuffle()
	for part in candidates.slice(0, 2):
		if _parts.damage_part(part, amount * 0.8):
			var away := global_position - (_last_hit_position if _last_hit_position != Vector3.ZERO else global_position + Vector3.DOWN)
			_parts.sever(part, away.normalized() + Vector3.UP)
			if _dead:
				return


func _on_part_severed(part: StringName, piece: RigidBody3D) -> void:
	var where := piece.global_position if piece != null else global_position + Vector3.UP
	limb_severed.emit(where, _last_hit_direction, _blood_exclusions())
	audio.severed(where)
	if _dead:
		return
	_part_lost(part)


# Consequences of a lost part; specialised enemies extend this.
func _part_lost(part: StringName) -> void:
	var name := String(part)
	if part == &"head":
		_die()
	elif name.begins_with("leg"):
		var legs: int = _parts.remaining("leg")
		if limb_loss_kills or legs == 0:
			_die()
		else:
			_mobility = minf(_mobility, 0.45)
	elif name.begins_with("arm") and _parts.remaining("arm") == 0:
		_attack_scale = 0.5


# Corpse hit volumes report here so blood still sprays on the floor.
func on_corpse_part_hit(_part: StringName, _damage: float, hit_position: Vector3, direction: Vector3, weapon: String) -> void:
	_last_hit_direction = direction
	projectile_blood.emit(hit_position, direction, weapon, _blood_exclusions(), get_instance_id())
	audio.hit(hit_position)


func apply_blast_stun(duration: float, intensity: float) -> void:
	_blast_stun_remaining = maxf(_blast_stun_remaining, duration * maxf(intensity, 0.25))


func apply_mutation_poison(duration: float, damage_per_second: float, parasite: bool = false) -> void:
	mutation_poison_remaining = maxf(mutation_poison_remaining, duration)
	_mutation_poison_damage = maxf(_mutation_poison_damage, damage_per_second)
	if parasite:
		set_meta("mutation_parasite", true)


func _physics_process(delta: float) -> void:
	_track_blood_motion()
	_blast_stun_remaining = maxf(0.0, _blast_stun_remaining - delta)
	if mutation_poison_remaining > 0.0:
		mutation_poison_remaining = maxf(0.0, mutation_poison_remaining - delta)
		take_damage(_mutation_poison_damage * delta)
	if _dead:
		velocity = Vector3.ZERO
		return
	if _target == null or not is_instance_valid(_target):
		return
	_tick_pending_hit(delta)

	var target_offset := _target.global_position - global_position
	target_offset.y = 0.0
	var distance_sq := target_offset.length_squared()
	var physics_frame := Engine.get_physics_frames()

	var far := distance_sq > sleep_distance * sleep_distance
	if far != _sleeping_far:
		_sleeping_far = far
		if _animation != null:
			_animation.call("set_active", not far)
	if far and physics_frame % 12 != _lod_frame_offset:
		return
	# A far enemy ticks every 12th frame, so its clocks advance 12 frames' worth.
	var step := delta * 12.0 if far else delta

	_attack_cooldown = maxf(0.0, _attack_cooldown - step)
	_obstacle_cooldown = maxf(0.0, _obstacle_cooldown - step)

	var near := distance_sq < full_simulation_distance * full_simulation_distance
	var ai_divisor := 1 if near else 4
	if physics_frame % ai_divisor == _ai_tick_offset % ai_divisor:
		_cached_desired = _desired_velocity_from_offset(target_offset)

	_behaviour_tick(step, target_offset)
	var desired := Vector3.ZERO if _blast_stun_remaining > 0.0 else _cached_desired
	if not _sleeping_far:
		_turn_toward_face_direction(delta)
	velocity.x = desired.x + _push_velocity.x
	velocity.z = desired.z + _push_velocity.z
	_push_velocity = _push_velocity.move_toward(Vector3.ZERO, push_decay * delta)

	if _sleeping_far:
		# Far enemies take one cheap collision-checked step (no sliding or
		# gravity), so they still stop at walls and closed doors.
		move_and_collide(Vector3(velocity.x, 0.0, velocity.z) * step)
		return

	_apply_gravity(delta)
	move_and_slide()
	audio.tick(delta, distance_sq <= charge_distance * charge_distance, distance_sq < 24.0 * 24.0)
	_push_chair_contacts()
	if near or physics_frame % 4 == _ai_tick_offset:
		_try_break_blocking_props()


func _desired_velocity_from_offset(offset: Vector3) -> Vector3:
	var distance := offset.length()
	if distance > 0.0001:
		_face_direction = offset / distance
	if distance <= attack_range:
		_try_attack()
		return Vector3.ZERO
	if distance <= 0.0001:
		return Vector3.ZERO
	return _face_direction * _chase_speed(distance)


func _chase_speed(distance: float) -> float:
	if charge_distance <= 0.0 or distance <= charge_distance:
		return move_speed * _mobility
	return move_speed * walk_speed_factor * _mobility


# Hook for specialised enemies (slam, ram, summon); runs every simulated tick.
func _behaviour_tick(_delta: float, _target_offset: Vector3) -> void:
	pass


func is_dead() -> bool:
	return _dead


# Smooth yaw turn toward the target; also while standing in attack range.
func _turn_toward_face_direction(delta: float) -> void:
	if _face_direction.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-_face_direction.x, -_face_direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))




func _push_chair_contacts() -> void:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()
		if collider != null and collider.has_method("push_from_character"):
			var movement := Vector3(velocity.x, 0.0, velocity.z)
			collider.call("push_from_character", global_position, movement)


func _try_break_blocking_props() -> void:
	if _obstacle_cooldown > 0.0:
		return
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()
		if collider != null and collider.is_in_group("infected_breakable_glass") and collider.has_method("take_melee_hit"):
			collider.call(
				"take_melee_hit",
				obstacle_damage,
				collision.get_position(),
				-global_transform.basis.z
			)
			_obstacle_cooldown = obstacle_attack_interval
			return




func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity_acceleration * delta


func _try_attack() -> void:
	if _attack_cooldown > 0.0 or _blast_stun_remaining > 0.0:
		return
	_attack_cooldown = attack_interval
	audio.attack_started()
	var duration := _play_animation(_attack_state())
	if duration <= 0.0:
		_deliver_attack()
		return
	_pending_hit = duration * attack_hit_fraction


func _tick_pending_hit(delta: float) -> void:
	if _pending_hit < 0.0:
		return
	if _blast_stun_remaining > 0.0:
		_pending_hit = -1.0
		return
	_pending_hit -= delta
	if _pending_hit < 0.0:
		_deliver_attack()


# The blow misses when the target has moved out of reach during the wind-up.
func _deliver_attack() -> void:
	if not is_instance_valid(_target) or not _target.has_method("take_damage"):
		return
	var offset := _target.global_position - global_position
	offset.y = 0.0
	if offset.length() > attack_range * attack_reach_tolerance:
		return
	_target.call("take_damage", attack_damage * _attack_scale)
	audio.attack_landed(_attack_scale < 1.0)


# Swing with whichever arm is still attached.
func _attack_state() -> StringName:
	if _parts == null:
		return &"attack"
	var left: bool = not _parts.is_severed(&"arm_l")
	var right: bool = not _parts.is_severed(&"arm_r")
	if left and not right:
		return &"attack_left"
	if right and not left:
		return &"attack_right"
	return &"attack"


func _play_animation(state: StringName) -> float:
	if _animation == null:
		return 0.0
	return float(_animation.call("play_one_shot", state))


func _blood_exclusions() -> Array[RID]:
	var excluded: Array[RID] = [get_rid()]
	return excluded


func _track_blood_motion() -> void:
	var current := global_position
	var travelled := current.distance_to(_blood_last_position)
	_blood_last_position = current
	if travelled > 3.0 or (not _dead and health >= max_health):
		_blood_segment_start = current
		_blood_distance = 0.0
		return
	_blood_distance += travelled
	var spacing := 0.35 if _dead else blood_drop_distance
	if _blood_distance < spacing:
		return
	if _dead:
		body_dragged.emit(_blood_segment_start, current, _blood_exclusions())
	else:
		wounded_moved.emit(_blood_segment_start, current, _blood_exclusions())
	_blood_distance = 0.0
	_blood_segment_start = current


func _die() -> void:
	_dead = true
	# An enemy killed while far had its animation paused; the death must play.
	_sleeping_far = false
	if _animation != null:
		_animation.call("set_active", true)
	audio.died()
	_pending_hit = -1.0
	_blood_segment_start = global_position
	_blood_distance = 0.0
	blood_death.emit(global_position, _blood_exclusions(), get_instance_id())
	if is_instance_valid(_target) and _target.has_method("mutation_enemy_killed"):
		_target.call("mutation_enemy_killed", self)
	# Infected summoned by a Horde drop nothing: an endless summon is no loot farm.
	if is_instance_valid(effects_root) and not has_meta("summoned_by"):
		var drop_table := DROP_TABLE_SCRIPT.new()
		effects_root.add_child(drop_table)
		drop_table.call("drop_for_enemy", effects_root, global_position)
		drop_table.queue_free()
	collision_layer = 0
	collision_mask = 0
	collision_shape.disabled = true
	if _parts != null:
		_parts.enable_corpse_hitboxes()
	var death_length := _play_animation(&"death")
	if death_length > 0.0:
		_sink_corpse_after(death_length)
	else:
		body_visual.visible = false
	death_cloud.call("activate")


# The corpse stays visible while the death animation plays, then sinks away.
func _sink_corpse_after(death_length: float) -> void:
	var tween := create_tween()
	tween.tween_interval(death_length + death_linger_seconds)
	tween.tween_property(body_visual, "position:y", body_visual.position.y - death_sink_depth, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(_hide_corpse)


func _hide_corpse() -> void:
	body_visual.hide()
	if _parts != null:
		_parts.remove_corpse_hitboxes()


func _on_death_cloud_depleted() -> void:
	queue_free()
