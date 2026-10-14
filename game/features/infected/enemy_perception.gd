extends RefCounted
## Sight and hearing for one infected (owner of its awareness state).
## UNAWARE stands still; a heard shot sends it to the noise (INVESTIGATE), where
## it looks around (SEARCH) and then walks back (RETURN). Seeing the player, being
## shot or hearing an ally's cry starts CHASE; a forced chase never ends.

enum State { UNAWARE, INVESTIGATE, SEARCH, RETURN, CHASE }

const ALERT_GROUP := "infected_alive"
const SIGHT_CHECK_SECONDS := 0.2
const SEARCH_SECONDS := 3.5
const INVESTIGATE_TIMEOUT := 14.0
const ARRIVE_DISTANCE := 1.4
const HOME_ARRIVE_DISTANCE := 0.8
const WALK_FACTOR := 0.6
const GLASS_GROUP := "infected_breakable_glass"

var state := State.CHASE
var forced := false
var sight_range := 18.0
var close_notice_range := 3.5
var fov_cos := cos(deg_to_rad(65.0))
var alert_radius := 16.0

var _home := Vector3.ZERO
var _home_yaw := 0.0
var _home_ready := false
var _noise := Vector3.ZERO
var _state_time := 0.0
var _sight_wait := 0.0
var _lure: Node3D


func watch() -> void:
	forced = false
	state = State.UNAWARE
	_home_ready = false


func force_chase() -> void:
	forced = true
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
	var offset := position - actor.global_position
	if offset.length() > radius:
		return
	if state != State.INVESTIGATE or position.distance_to(_noise) > 2.0:
		_state_time = 0.0
	_noise = position
	state = State.INVESTIGATE


func alert() -> bool:
	if state == State.CHASE:
		return false
	state = State.CHASE
	return true


# One physics step while not chasing: look, listen, walk to a noise or back home.
func step_unaware(actor: CharacterBody3D, delta: float) -> void:
	var target: Node3D = actor.get("_target")
	var far := actor.global_position.distance_squared_to(target.global_position) > pow(float(actor.get("sleep_distance")), 2.0)
	if far and state == State.UNAWARE and Engine.get_physics_frames() % 12 != int(actor.get("_lod_frame_offset")):
		return
	var radius := .35
	var shape: CollisionShape3D = actor.get("collision_shape")
	if shape != null and shape.shape is CapsuleShape3D:
		radius = (shape.shape as CapsuleShape3D).radius * actor.global_basis.x.length()
	var speed := float(actor.get("move_speed")) * float(actor.get("_mobility"))
	var wish := tick(actor, delta, target, actor.get("_route"), radius, speed)
	if float(actor.get("_blast_stun_remaining")) > 0.0:
		wish = Vector3.ZERO
	actor.call("_turn_toward_face_direction", delta)
	var push: Vector3 = actor.get("_push_velocity")
	actor.velocity.x = wish.x + push.x
	actor.velocity.z = wish.z + push.z
	actor.set("_push_velocity", push.move_toward(Vector3.ZERO, float(actor.get("push_decay")) * delta))
	actor.call("_apply_gravity", delta)
	actor.set("_intended_motion", Vector3(actor.velocity.x, 0.0, actor.velocity.z))
	actor.move_and_slide()
	actor.call("_push_chair_contacts")


# Desired horizontal velocity while not chasing; may switch to CHASE.
func tick(actor: CharacterBody3D, delta: float, target: Node3D, route, radius: float, speed: float) -> Vector3:
	if not _home_ready:
		_home = actor.global_position
		_home_yaw = actor.rotation.y
		_home_ready = true
	_state_time += delta
	_sight_wait -= delta
	if _sight_wait <= 0.0:
		_sight_wait = SIGHT_CHECK_SECONDS + float(actor.get_instance_id() % 7) * 0.01
		if can_see(actor, target):
			state = State.CHASE
			return Vector3.ZERO
	match state:
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


func _walk(actor: CharacterBody3D, route, goal: Vector3, radius: float, speed: float, arrive: float, next: State) -> Vector3:
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
		actor.set("_face_direction", dir)
	return dir * speed


func _enter(next: State) -> void:
	state = next
	_state_time = 0.0


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
