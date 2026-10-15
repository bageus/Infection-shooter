extends RefCounted
## Sight and hearing for one infected (owner of its awareness state).
## UNAWARE stands still; a heard shot sends it to the noise (INVESTIGATE), where
## it looks around (SEARCH) and then walks back (RETURN). Seeing the player, being
## shot or hearing an ally's cry starts CHASE; a forced chase never ends.

const ACTOR := preload("res://game/features/infected/infected_capsule.gd")
const IDLE_BODY := preload("res://game/features/infected/enemy_idle_body.gd")
const ROUTE := preload("res://game/features/infected/chase_route.gd")

enum State { UNAWARE, INVESTIGATE, SEARCH, RETURN, CHASE }

const ALERT_GROUP := "infected_alive"
const SIGHT_CHECK_SECONDS := 0.2
const SEARCH_SECONDS := 3.5
const INVESTIGATE_TIMEOUT := 14.0
const ARRIVE_DISTANCE := 1.4
const HOME_ARRIVE_DISTANCE := 0.8
const WALK_FACTOR := 0.6
const WANDER_FACTOR := 0.35
const WANDER_MIN := 1.0
const WANDER_MAX := 3.0
const WANDER_TIMEOUT := 6.0
const GLASS_GROUP := "infected_breakable_glass"

var state := State.CHASE
var forced := false
var wander_enabled := true
var sight_range := 18.0
var close_notice_range := 3.5
var fov_cos := cos(deg_to_rad(65.0))
var hearing := preload("res://game/features/infected/hearing_profile.gd").new()
var _alert_announced := false

var _home := Vector3.ZERO
var _home_yaw := 0.0
var _home_ready := false
var _noise := Vector3.ZERO
var _state_time := 0.0
var _sight_wait := randf_range(0.0, SIGHT_CHECK_SECONDS)
var _lure: Node3D
var _wander := Vector3.ZERO
var _wandering := false
var _wander_wait := 1.0
var _idle_elapsed := 0.0
var _idle_body: IDLE_BODY


func watch() -> void:
	forced = false
	state = State.UNAWARE
	_home_ready = false
	_idle_elapsed = 0.0


func force_chase() -> void:
	_idle_elapsed = 0.0
	forced = true
	_alert_announced = true
	state = State.CHASE


func is_chasing() -> bool:
	return state == State.CHASE


func is_unaware() -> bool:
	return state == State.UNAWARE


func noise_position() -> Vector3:
	return _noise


func hear(actor: Node3D, position: Vector3, radius: float) -> void:
	if state == State.CHASE:
		return
	if not hearing.reaches(actor, position, radius):
		return
	if state != State.INVESTIGATE or position.distance_to(_noise) > hearing.investigate_refresh_distance:
		_state_time = 0.0
	_noise = position
	_idle_elapsed = 0.0
	state = State.INVESTIGATE


func hear_ally(actor: Node3D, position: Vector3, radius: float) -> void:
	if state != State.CHASE and hearing.reaches(actor, position + Vector3.UP * hearing.ear_height, radius):
		alert()
		_alert_announced = true


func notice_player(actor: Node3D, audio: Node) -> void:
	var newly_alerted := alert()
	if newly_alerted or not _alert_announced:
		_alert_announced = true
		audio.call("alert_shout")
		actor.get_tree().call_group(ALERT_GROUP, "hear_alert", actor.global_position, hearing.alert_radius)


func alert() -> bool:
	if state == State.CHASE:
		return false
	_idle_elapsed = 0.0
	state = State.CHASE
	return true


# One physics step while not chasing: look, listen, walk to a noise or back home.
func step_unaware(actor: ACTOR, delta: float) -> void:
	if _idle_body == null:
		_idle_body = IDLE_BODY.new()
	var target: Node3D = actor._target
	_idle_elapsed += delta
	if _check_sight(actor, target, delta):
		_idle_elapsed = 0.0
		return
	var distance_sq := actor.global_position.distance_squared_to(target.global_position)
	var push: Vector3 = actor._push_velocity
	var disturbed := not push.is_zero_approx() or actor._blast_stun_remaining > 0.0
	var supported := actor.is_on_floor()
	var support_checked := supported and (distance_sq >= actor.full_simulation_distance * actor.full_simulation_distance or actor.velocity.is_zero_approx())
	if support_checked:
		supported = _idle_body.supported(actor)
	var divisor := 1
	if state == State.UNAWARE and supported and not disturbed:
		if distance_sq > actor.sleep_distance * actor.sleep_distance:
			divisor = 12
		elif distance_sq >= actor.full_simulation_distance * actor.full_simulation_distance:
			divisor = 3
	if Engine.get_physics_frames() % divisor != actor._lod_frame_offset % divisor:
		actor._turn_toward_face_direction(delta)
		actor._apply_gravity(delta)
		return
	var step := _idle_elapsed
	_idle_elapsed = 0.0
	var radius := _idle_body.radius(actor.collision_shape, actor.global_basis.x.length())
	var speed := actor.move_speed * actor._mobility
	var wish := tick(actor, step, target, actor._route, radius, speed, false)
	if actor._blast_stun_remaining > 0.0:
		wish = Vector3.ZERO
	actor._turn_toward_face_direction(delta)
	actor.velocity.x = wish.x + push.x
	actor.velocity.z = wish.z + push.z
	actor._push_velocity = push.move_toward(Vector3.ZERO, actor.push_decay * delta)
	actor._apply_gravity(delta)
	actor._intended_motion = Vector3(actor.velocity.x, 0.0, actor.velocity.z)
	# UNAWARE has no crowd steering in the existing behavior (spread is zero).
	if wish.is_zero_approx() and not disturbed and supported and (support_checked or _idle_body.supported(actor)):
		return
	if divisor > 1:
		var motion := Vector3(actor.velocity.x, 0.0, actor.velocity.z) * step
		if _wandering:
			var remaining := _wander - actor.global_position
			remaining.y = 0.0
			motion = motion.limit_length(remaining.length())
		if divisor == 12:
			actor.move_and_collide(motion)
		else:
			_collide(actor, motion)
	else:
		_slide(actor)


func _slide(actor: ACTOR) -> void:
	actor.move_and_slide()
	actor._push_chair_contacts()


# Collision-checked LOD travel retains tangential motion and prop pushes.
func _collide(actor: ACTOR, motion: Vector3) -> void:
	var pushed: Object = null
	for i in 2:
		var hit := actor.move_and_collide(motion)
		if hit == null:
			return
		var collider := hit.get_collider()
		if collider != null and collider != pushed and collider.has_method("push_from_character"):
			pushed = collider
			collider.call("push_from_character", actor.global_position, actor._intended_motion, actor.push_strength)
		motion = hit.get_remainder().slide(hit.get_normal())
		if motion.is_zero_approx():
			return


func _check_sight(actor: CharacterBody3D, target: Node3D, delta: float) -> bool:
	_sight_wait -= delta
	if _sight_wait <= 0.0:
		_sight_wait = SIGHT_CHECK_SECONDS + float(actor.get_instance_id() % 7) * 0.01
		if can_see(actor, target):
			state = State.CHASE
			return true
	return false


# Desired horizontal velocity while not chasing; may switch to CHASE.
func tick(actor: CharacterBody3D, delta: float, target: Node3D, route: ROUTE, radius: float, speed: float, check_sight := true) -> Vector3:
	if not _home_ready:
		_home = actor.global_position
		_home_yaw = actor.rotation.y
		_home_ready = true
	_state_time += delta
	if check_sight and _check_sight(actor, target, delta):
		return Vector3.ZERO
	match state:
		State.UNAWARE:
			return _idle_wander(actor, delta, route, radius, speed)
		State.INVESTIGATE:
			return _walk(actor, route, _noise, radius, speed * WALK_FACTOR, ARRIVE_DISTANCE, State.SEARCH)
		State.SEARCH:
			if _state_time >= SEARCH_SECONDS:
				_enter(State.RETURN)
			return Vector3.ZERO
		State.RETURN:
			var back := _walk(actor, route, _home, radius, speed * WALK_FACTOR, HOME_ARRIVE_DISTANCE, State.UNAWARE)
			if state == State.UNAWARE:
				actor.rotation.y = _home_yaw
			return back
	return Vector3.ZERO


# At its post an unaware infected strolls 1-3 m from home in a random direction, pausing between steps.
func _idle_wander(actor: CharacterBody3D, delta: float, route: ROUTE, radius: float, speed: float) -> Vector3:
	if not wander_enabled:
		return Vector3.ZERO
	if not _wandering:
		_wander_wait -= delta
		if _wander_wait <= 0.0:
			var angle := randf() * TAU
			_wander = _home + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(WANDER_MIN, WANDER_MAX)
			_wandering = true
			_state_time = 0.0
		return Vector3.ZERO
	var flat := _wander - actor.global_position
	flat.y = 0.0
	if flat.length() <= 0.4 or _state_time > WANDER_TIMEOUT:
		_wandering = false
		_wander_wait = randf_range(1.5, 4.0)
		return Vector3.ZERO
	# A batched distant step can cover 12 physics ticks; stop at the goal
	# instead of overshooting it and leaving the authored wander radius.
	var walk_speed := minf(speed * WANDER_FACTOR, flat.length() / delta) if delta > 0.0 else 0.0
	return _walk(actor, route, _wander, radius, walk_speed, 0.4, State.UNAWARE)


func _walk(actor: CharacterBody3D, route: ROUTE, goal: Vector3, radius: float, speed: float, arrive: float, next: State) -> Vector3:
	var flat := goal - actor.global_position
	flat.y = 0.0
	if flat.length() <= arrive or _state_time > INVESTIGATE_TIMEOUT:
		_enter(next)
		return Vector3.ZERO
	if _lure == null or not is_instance_valid(_lure):
		_lure = Node3D.new()
		_lure.top_level = true
		actor.add_child(_lure)
	_lure.global_position = goal
	var dir: Vector3 = route.direction(actor, _lure, radius)
	if not dir.is_zero_approx():
		(actor as ACTOR)._face_direction = dir
	return dir * speed


func _enter(next: State) -> void:
	state = next
	_state_time = 0.0
	_wandering = false


func can_see(actor: Node3D, target: Node3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var to := target.global_position - actor.global_position
	to.y = 0.0
	var distance := to.length()
	if distance > sight_range:
		return false
	if distance > close_notice_range:
		var forward := -actor.global_basis.z
		forward.y = 0.0
		if forward.normalized().dot(to / distance) < fov_cos:
			return false
	return _line_clear(actor, target)


# Walls and doors hide the player; glass panes do not.
func _line_clear(actor: Node3D, target: Node3D) -> bool:
	var space := actor.get_world_3d().direct_space_state
	var from := actor.global_position + Vector3.UP * 1.5
	var to := target.global_position + Vector3.UP * 1.1
	var excluded: Array[RID] = []
	if actor is CollisionObject3D:
		excluded.append((actor as CollisionObject3D).get_rid())
	if target is CollisionObject3D:
		excluded.append((target as CollisionObject3D).get_rid())
	for _i in 3:
		var query := PhysicsRayQueryParameters3D.create(from, to, 1, excluded)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return true
		var collider: Object = hit.collider
		if not (collider is Node and (collider as Node).is_in_group(GLASS_GROUP)):
			return false
		excluded.append(hit.rid)
	return false
