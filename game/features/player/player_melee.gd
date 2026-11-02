extends RefCounted
## The strike on the melee key (ADR-0066). With an enemy close by the player
## jabs with the left hand; otherwise a kick breaks loot crates at once and
## throws every other loose object away from the character. The next strike
## is blocked for COOLDOWN seconds (no indicator). Presentation of the pose is
## the animation driver's job; this owns timing and the effect on the world.

const KICK := &"kick"
const PUNCH := &"punch"
const COOLDOWN := 2.0
## An enemy whose surface is this close makes the strike a hand jab.
const NEAR_ENEMY := 2.0
const PUNCH_REACH := 1.1
const PUNCH_DAMAGE := 17.0
const KICK_LENGTH := 1.7
const KICK_WIDTH := 1.8
const KICK_HEIGHT := 1.2
## Impulse (kg*m/s) behind a kick, split by the item's mass and capped in speed.
const KICK_IMPULSE := 90.0
const KICK_MIN_SPEED := 1.5
const KICK_MAX_SPEED := 8.0
const OBJECT_MASK := 7
const OBJECT_QUERY_LIMIT := 32
## Seconds from the key press to the foot or fist landing (strike_pose.gd).
const IMPACT_DELAY := {KICK: 0.27, PUNCH: 0.14}

var cooldown := 0.0
var _host: Node
var _pending: StringName = &""
var _delay := 0.0


func configure(host: Node) -> void:
	_host = host


func tick(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	if _pending == &"":
		return
	_delay -= delta
	if _delay > 0.0:
		return
	var kind := _pending
	_pending = &""
	if kind == KICK:
		_kick_impact()
	else:
		_punch_impact()


## Starts a strike; returns its kind, or &"" while the cooldown runs.
func start() -> StringName:
	if cooldown > 0.0:
		return &""
	cooldown = COOLDOWN
	_pending = PUNCH if enemy_close() else KICK
	_delay = float(IMPACT_DELAY[_pending])
	var driver: Node = _host.player.get_node_or_null("AnimationDriver")
	if driver != null:
		driver.call("play_strike", _pending)
	return _pending


func enemy_close() -> bool:
	var origin: Vector3 = _host.player.global_position
	for enemy in _host._enemies_near(origin, NEAR_ENEMY + 1.0):
		if _flat_offset(enemy).length() - _host._body_radius(enemy) <= NEAR_ENEMY:
			return true
	return false


func _punch_impact() -> void:
	var forward := _forward()
	for enemy in _host._enemies_near(_host.player.global_position, PUNCH_REACH + 2.5, true):
		var offset: Vector3 = _flat_offset(enemy)
		if offset.length() - _host._body_radius(enemy) > PUNCH_REACH or offset.normalized().dot(forward) <= 0.0:
			continue
		enemy.call("take_damage", _host._scented(enemy, PUNCH_DAMAGE))
		return


func _kick_impact() -> void:
	var player: CharacterBody3D = _host.player
	var forward := _forward()
	var box := BoxShape3D.new()
	box.size = Vector3(KICK_WIDTH, KICK_HEIGHT, KICK_LENGTH)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = Transform3D(Basis.looking_at(forward), player.global_position + forward * KICK_LENGTH * 0.5 + Vector3.UP * (KICK_HEIGHT * 0.5 + 0.1))
	query.collision_mask = OBJECT_MASK
	query.exclude = [player.get_rid()]
	var seen := {}
	var nearest_crate: Node3D = null
	for hit in player.get_world_3d().direct_space_state.intersect_shape(query, OBJECT_QUERY_LIMIT):
		var body := hit.get("collider") as Node3D
		if body == null or seen.has(body.get_instance_id()) or body is CharacterBody3D:
			continue
		seen[body.get_instance_id()] = true
		if body.has_method("has_loot") and bool(body.call("has_loot")) and body.has_method("break_by_strike"):
			if nearest_crate == null or body.global_position.distance_squared_to(player.global_position) < nearest_crate.global_position.distance_squared_to(player.global_position):
				nearest_crate = body
		elif body is RigidBody3D and not (body as RigidBody3D).freeze and not _is_creature(body):
			_throw(body as RigidBody3D, player.global_position)
	# One kick breaks the nearest crate only; a crowd of crates takes one kick each.
	if nearest_crate != null:
		nearest_crate.call("break_by_strike", nearest_crate.global_position, forward)


# Flings a loose item away from the character; heavy ones barely move.
static func _throw(body: RigidBody3D, from: Vector3) -> void:
	var away := body.global_position - from
	away.y = 0.0
	if away.length_squared() < 0.0001:
		return
	var speed := clampf(KICK_IMPULSE / maxf(body.mass, 0.01), KICK_MIN_SPEED, KICK_MAX_SPEED)
	body.sleeping = false
	body.apply_central_impulse((away.normalized() + Vector3.UP * 0.25) * speed * body.mass)
	body.apply_torque_impulse(Vector3.UP.cross(away.normalized()) * speed * body.mass * 0.08)


static func _is_creature(body: Node) -> bool:
	return body.is_in_group("infected") or body.is_in_group("player") or body.is_in_group("contactless_debris")


func _forward() -> Vector3:
	var forward := -(_host.player.get_node("AimPivot") as Node3D).global_basis.z
	forward.y = 0.0
	return forward.normalized()


func _flat_offset(enemy: Node3D) -> Vector3:
	var offset: Vector3 = enemy.global_position - _host.player.global_position
	offset.y = 0.0
	return offset
