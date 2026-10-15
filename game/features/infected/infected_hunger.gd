extends "res://game/features/infected/infected_capsule.gd"
## Hunger with the full-body Mixamo clips (ADR-0045).
##
## Postures: upright, on all fours (a feral sprint, or a badly hurt hunter), and
## belly crawl after a leg is shot off. At rest it idles, now and then groans or
## screams (flavour only), turns on the spot to change direction and gnaws a
## nearby corpse. The first hunter that notices the player screams before it
## runs and its cry calls the neighbours, who run without screaming.

enum Posture { STAND, FOURS, CRAWL }

const SCREAM := &"Scream"
const CRAWL_MOBILITY := 0.28
const FOURS_START_DISTANCE := 7.0
const FOURS_STAND_DISTANCE := 4.5
const FERAL_SHARE := 0.35
const WOUNDED_RATIO := 0.4
const RUN_SPEED := 3.78
const RUN_EXIT_RATIO := 0.85
const LUNGE_DISTANCE := 6.0
const TURN_MIN_ANGLE := 1.3 # rad, about 75 degrees
const TURN_SPEED := 1.25
const IDLE_WAIT := Vector2(10.0, 25.0)
const CORPSE_RANGE := 8.0
const CORPSE_CHECK := 2.5
const FEED_SECONDS := Vector2(5.0, 10.0)
const HIT_FLINCH_STRENGTH := 0.75
const HIT_COOLDOWN := 1.6
const SIGHT_CHECK := 0.2

@export var rest_behaviours := true # in-place turns, idle flavour and feeding when unaware
var posture := Posture.STAND
var _busy := 0.0
var _distance := INF
var _feral := false
var _running := false
var _skip_scream := false
var _aggro_pending := false
var _aggro_done := false
var _spring_only := false
var _hit_cooldown := 0.0
var _idle_wait := randf_range(IDLE_WAIT.x, IDLE_WAIT.y)
var _turn_time := -1.0
var _turn_length := 1.0
var _turn_from := 0.0
var _turn_angle := 0.0
var _turn_curve := PackedFloat32Array()
var _feeding := false
var _feed_left := 0.0
var _corpse: Node3D
var _corpse_wait := randf_range(1.0, CORPSE_CHECK)
var _sight_wait := 0.0


func _ready() -> void:
	super._ready()
	_feral = randf() < FERAL_SHARE
	if _animation != null:
		_animation.call("configure_clip_selector", _clip_for_state)


func is_feeding() -> bool: return _feeding


func is_busy() -> bool: return _busy > 0.0


# Spawners and summons force the chase: nothing to scream about.
func set_target(target: Node3D) -> void:
	_skip_scream = true
	super.set_target(target)


# A neighbour's cry makes this one run without screaming itself.
func hear_alert(at: Vector3, radius: float) -> void:
	if not _dead and not is_alerted() and at.distance_to(global_position) <= radius:
		_skip_scream = true
	super.hear_alert(at, radius)


# Blasts rock the torso with the directional spring, not the shot flinch clip.
func take_blast_damage(amount: float, origin: Vector3) -> void:
	_spring_only = true
	super.take_blast_damage(amount, origin)
	_spring_only = false


# Sight and shots start the chase; the shout itself is _on_aggro's.
func _notice_player() -> void:
	if _senses.alert():
		_aggro_pending = true


func _physics_process(delta: float) -> void:
	_busy = maxf(0.0, _busy - delta)
	_hit_cooldown = maxf(0.0, _hit_cooldown - delta)
	super._physics_process(delta)
	# Sight, a shot or a cry may have started the chase since the last tick.
	if not _dead and is_instance_valid(_target) and is_alerted() and not _aggro_done:
		_aggro_done = true
		_on_aggro()


# ------------------------------------------------------------ animation

func _clip_for_state() -> StringName:
	var speed := Vector2(velocity.x, velocity.z).length()
	match posture:
		Posture.CRAWL:
			return &"Crawl" if speed > 0.15 else &"CrawlIdle"
		Posture.FOURS:
			return &"FoursRun" if speed > 0.15 else &"FoursIdle"
	if _feeding:
		return &"BiteLoop"
	_running = speed > RUN_SPEED * (RUN_EXIT_RATIO if _running else 1.0)
	if _running:
		return &"RunLunge" if _pace.charging and _distance < LUNGE_DISTANCE else &"Run"
	return &"Walk" if speed > 0.15 else &"Idle"


# Plays a clip that holds the hunter in place; returns its length.
func _start_busy(clip: StringName, speed: float = 1.0) -> float:
	_busy = 0.0
	if _animation != null:
		_busy = float(_animation.call("play_named_one_shot", clip, 0.12, speed))
	return _busy


func _attack_state() -> StringName:
	return &"attack_crawl" if posture == Posture.CRAWL else super._attack_state()


# On all fours it stands up first; the clip that lets it do so is the busy time.
func _try_attack() -> void:
	if _busy > 0.0:
		return
	if posture == Posture.FOURS:
		posture = Posture.STAND
		_start_busy(&"RiseFromFours")
		return
	super._try_attack()


func _react_to_hit(strength: float) -> void:
	var flinch := posture == Posture.STAND and not _feeding and _busy <= 0.0 and not _aggro_pending and not _spring_only
	if flinch and strength >= HIT_FLINCH_STRENGTH and _hit_cooldown <= 0.0 and _animation != null:
		if bool(_animation.call("play_overlay", &"HitReaction")):
			_hit_cooldown = HIT_COOLDOWN
			return
	super._react_to_hit(strength)


# ------------------------------------------------------------ chase

func _on_aggro() -> void:
	_aggro_pending = false
	_turn_time = -1.0
	var cries := not _skip_scream
	_skip_scream = false
	var from_corpse := _feeding
	if from_corpse:
		# Up from the corpse straight into a run on all fours.
		_end_feeding(false)
		posture = Posture.FOURS
	if not cries:
		return
	audio.alert_shout()
	get_tree().call_group(PERCEPTION.ALERT_GROUP, "hear_alert", global_position, _senses.hearing.alert_radius)
	if not from_corpse and posture != Posture.CRAWL:
		_start_busy(SCREAM)


func _behaviour_tick(_delta: float, target_offset: Vector3) -> void:
	_distance = target_offset.length()
	if _busy > 0.0:
		_cached_desired = Vector3.ZERO
		return
	_update_posture()


func _update_posture() -> void:
	var wounded := health < max_health * WOUNDED_RATIO
	if posture == Posture.STAND:
		if (_pace.charging or wounded) and _distance > FOURS_START_DISTANCE and (_feral or wounded):
			posture = Posture.FOURS
	elif posture == Posture.FOURS:
		if _distance < FOURS_STAND_DISTANCE or not (_pace.charging or wounded):
			posture = Posture.STAND


func _part_lost(part: StringName) -> void:
	super._part_lost(part)
	if not _dead and String(part).begins_with("leg") and posture != Posture.CRAWL:
		_collapse()


# A leg is gone: the hunter drops to its belly and drags itself on.
func _collapse() -> void:
	var from_low := posture == Posture.FOURS or _feeding
	posture = Posture.CRAWL
	_mobility = minf(_mobility, CRAWL_MOBILITY)
	_feeding = false
	audio.feeding_tick(0.0, false)
	audio.stop_voice()
	_turn_time = -1.0
	_pending_hit = -1.0
	_start_busy(&"FoursToCrawl" if from_low else &"CollapseToCrawl")


func _die() -> void:
	_busy = 0.0
	_feeding = false
	_turn_time = -1.0
	super._die()


# ------------------------------------------------------------ at rest

func _unaware_tick(delta: float) -> void:
	if _turn_time >= 0.0:
		_step_turn(delta)
		return
	if _busy > 0.0 or _feeding:
		_hold_still(delta)
		return
	if not rest_behaviours:
		super._unaware_tick(delta)
		return
	var yaw_before := rotation.y
	var standing := Vector2(velocity.x, velocity.z).length() < 0.3
	super._unaware_tick(delta)
	if _senses.is_chasing() or posture != Posture.STAND:
		return
	if standing and _senses.state in [PERCEPTION.State.UNAWARE, PERCEPTION.State.RETURN] and _start_turn_if_needed(yaw_before):
		return
	if standing:
		_rest_behaviour(delta)


# Stands still (gravity and pushes only) but keeps watching for the player.
func _hold_still(delta: float) -> void:
	_sight_wait -= delta
	if _sight_wait <= 0.0:
		_sight_wait = SIGHT_CHECK
		if _senses.can_see(self, _target):
			_notice_player()
			return
	if _feeding:
		_feed(delta)
	_turn_toward_face_direction(delta)
	var push := _push_velocity
	velocity.x = push.x
	velocity.z = push.z
	_push_velocity = push.move_toward(Vector3.ZERO, push_decay * delta)
	_apply_gravity(delta)
	move_and_slide()


func _turn_toward_face_direction(delta: float) -> void:
	if _turn_time < 0.0:
		super._turn_toward_face_direction(delta)


# Wants to walk off the other way: turn on the spot with the turn clip instead.
func _start_turn_if_needed(yaw_before: float) -> bool:
	if _face_direction.length_squared() < 0.0001:
		return false
	var wanted := atan2(-_face_direction.x, -_face_direction.z)
	var angle := wrapf(wanted - yaw_before, -PI, PI)
	if absf(angle) < TURN_MIN_ANGLE or _animation == null:
		return false
	var clip := &"TurnLeft" if angle > 0.0 else &"TurnRight"
	var curve: PackedFloat32Array = _animation.call("clip_meta", clip, &"yaw_curve", PackedFloat32Array())
	var total := float(_animation.call("clip_meta", clip, &"turn_yaw", 0.0))
	if curve.size() < 2 or absf(total) < 0.1:
		return false
	var length := _start_busy(clip, TURN_SPEED)
	if length <= 0.0:
		return false
	rotation.y = yaw_before
	velocity = Vector3(0.0, velocity.y, 0.0)
	_turn_curve = curve
	_turn_length = length
	_turn_from = yaw_before
	_turn_angle = angle
	_turn_time = 0.0
	return true


func _step_turn(delta: float) -> void:
	_turn_time += delta
	var done := _turn_time >= _turn_length
	var frame := clampf(_turn_time * TURN_SPEED * 30.0, 0.0, float(_turn_curve.size() - 1))
	var low := int(floor(frame))
	var high := mini(low + 1, _turn_curve.size() - 1)
	var progress := lerpf(_turn_curve[low], _turn_curve[high], frame - floor(frame)) / _turn_curve[_turn_curve.size() - 1]
	rotation.y = _turn_from + _turn_angle * (1.0 if done else clampf(progress, 0.0, 1.0))
	if done:
		_turn_time = -1.0
	velocity.x = 0.0
	velocity.z = 0.0
	_apply_gravity(delta)
	move_and_slide()


# Idle flavour (groan, harmless scream) and gnawing at corpses.
func _rest_behaviour(delta: float) -> void:
	if _senses.state == PERCEPTION.State.SEARCH and _corpse != null:
		_begin_feeding()
		return
	if _senses.state != PERCEPTION.State.UNAWARE:
		return
	_idle_wait -= delta
	_corpse_wait -= delta
	if _corpse_wait <= 0.0:
		_corpse_wait = CORPSE_CHECK
		var corpse := _find_corpse()
		if corpse != null and randf() < 0.5:
			_corpse = corpse
			_senses.hear(self, corpse.global_position, CORPSE_RANGE + 1.0)
			return
	if _idle_wait <= 0.0:
		_idle_wait = randf_range(IDLE_WAIT.x, IDLE_WAIT.y)
		_idle_flavor(randf() >= 0.55)


# A groan, or the chase's scream as pure flavour: it alerts nobody.
func _idle_flavor(scream: bool) -> void:
	if scream:
		_start_busy(SCREAM)
		audio.idle_scream()
	else:
		if _start_busy(&"Agonize") > 0.0:
			audio.agony()


func _find_corpse() -> Node3D:
	var best: Node3D
	var best_distance := CORPSE_RANGE * CORPSE_RANGE
	for node in get_tree().get_nodes_in_group("infected"):
		var other := node as Node3D
		if other == null or other == self or other.is_in_group(ALIVE_GROUP) or not other.has_method("is_dead") or not bool(other.call("is_dead")):
			continue
		var visual := other.get("body_visual") as Node3D
		if visual == null or not visual.visible:
			continue
		var distance := other.global_position.distance_squared_to(global_position)
		if distance < best_distance:
			best = other
			best_distance = distance
	return best


func _begin_feeding() -> void:
	if not is_instance_valid(_corpse) or not (_corpse.get("body_visual") as Node3D).visible or _corpse.global_position.distance_to(global_position) > 3.0:
		_corpse = null
		return
	var toward := _corpse.global_position - global_position
	toward.y = 0.0
	if toward.length_squared() > 0.01:
		_face_direction = toward.normalized()
	_feeding = true
	_feed_left = randf_range(FEED_SECONDS.x, FEED_SECONDS.y)
	_start_busy(&"BiteDown")


func _feed(delta: float) -> void:
	audio.feeding_tick(delta, _busy <= 0.0)
	_feed_left -= delta
	var gone := not is_instance_valid(_corpse) or not (_corpse.get("body_visual") as Node3D).visible
	if _busy <= 0.0 and (_feed_left <= 0.0 or gone or _senses.state != PERCEPTION.State.SEARCH):
		_end_feeding(true)


func _end_feeding(stand_up: bool) -> void:
	audio.feeding_tick(0.0, false)
	audio.stop_voice()
	_feeding = false
	_corpse = null
	if stand_up:
		_start_busy(&"BiteUp")
