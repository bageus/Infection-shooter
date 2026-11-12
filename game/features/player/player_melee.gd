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
## The player origin is the capsule centre; the floor is this far below it.
const PLAYER_HALF_HEIGHT := 0.9
## Damage a kick deals to a prop it hits (tables, nightstands); a few kicks break one.
const KICK_OBJECT_DAMAGE := 50.0
const HIT_EVENTS := {"metal": &"hit_metal", "tech": &"hit_electronics", "glass": &"hit_glass"}
const SFX := preload("res://game/core/audio/public/sound_events.gd")
const KICK_WIDTH := 1.8
const KICK_HEIGHT := 1.2
## Impulse (kg*m/s) behind a kick, split by the item's mass and capped in speed.
const KICK_IMPULSE := 25.0 # heavy items move only a little; was 90, which sent a 27 kg cabinet at 3.3 m/s
const KICK_MAX_SPEED := 8.0
## Metres a kick shoves an enemy it lands on.
const KICK_ENEMY_PUSH := 1.0
## Metres a jab shoves the enemy it hits.
const PUNCH_ENEMY_PUSH := 0.4
const OBJECT_MASK := 7
## Default physics layer: walls, floors and props, not the enemy layers.
const WALL_MASK := 1
## Debris fills the box, so the cap is high: a crate under a crowd of pieces must still be returned.
const OBJECT_QUERY_LIMIT := 256
const LINE_CHECK_PASSES := 16
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
		SFX.play(enemy, &"loud_flesh_hit_1")
		if enemy.has_method("apply_skill_push"):
			enemy.call("apply_skill_push", forward, PUNCH_ENEMY_PUSH)
		return


func _kick_impact() -> void:
	var player: CharacterBody3D = _host.player
	var forward := _forward()
	var box := BoxShape3D.new()
	box.size = Vector3(KICK_WIDTH, KICK_HEIGHT, KICK_LENGTH)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = Transform3D(Basis.looking_at(forward), player.global_position + Vector3.DOWN * PLAYER_HALF_HEIGHT + forward * KICK_LENGTH * 0.5 + Vector3.UP * (KICK_HEIGHT * 0.5 + 0.1))
	query.collision_mask = OBJECT_MASK
	query.exclude = [player.get_rid()]
	var seen := {}
	var nearest_crate: Node3D = null
	for hit in player.get_world_3d().direct_space_state.intersect_shape(query, OBJECT_QUERY_LIMIT):
		var body := hit.get("collider") as Node3D
		if body == null or seen.has(body.get_instance_id()) or body is CharacterBody3D:
			continue
		seen[body.get_instance_id()] = true
		if not _clear_line(body):
			continue
		if body.has_method("has_loot") and bool(body.call("has_loot")) and body.has_method("break_by_strike"):
			if nearest_crate == null or body.global_position.distance_squared_to(player.global_position) < nearest_crate.global_position.distance_squared_to(player.global_position):
				nearest_crate = body
		elif not _is_creature(body):
			_kick_object(body, forward)
	for enemy in _host._enemies_near(player.global_position, KICK_LENGTH + 1.5):
		var offset := _flat_offset(enemy)
		var reach := float(_host._body_radius(enemy))
		if enemy.has_method("apply_skill_push") and offset.dot(forward) > 0.0 and offset.dot(forward) <= KICK_LENGTH + reach and absf(offset.cross(forward).y) <= KICK_WIDTH * 0.5 + reach and _clear_line(enemy):
			enemy.call("apply_skill_push", forward, KICK_ENEMY_PUSH)
			SFX.play(enemy, &"loud_dull_flesh_foot_1")
	# One kick breaks the nearest crate only; a crowd of crates takes one kick each.
	if nearest_crate != null:
		nearest_crate.call("break_by_strike", nearest_crate.global_position, forward)


# Walls and floor block the kick: the target is reachable only if the first static hit on the way is the target.
func _clear_line(target: Node3D) -> bool:
	var player: CharacterBody3D = _host.player
	var query := PhysicsRayQueryParameters3D.create(player.global_position, target.global_position, WALL_MASK)
	query.exclude = [player.get_rid()]
	for _pass in LINE_CHECK_PASSES:
		var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.collider == target or target.is_ancestor_of(hit.collider):
			return true
		if not hit.collider is RigidBody3D:
			return false # static geometry: a wall or floor
		var excluded := query.exclude # Godot hands out a copy, so assign it back
		excluded.append(hit.rid) # loose props in the way do not block the kick
		query.exclude = excluded
	return false


# A kick hits any prop the punch can hit (tables, nightstands, glass) and thuds; loose items also fly.
func _kick_object(hit: Node3D, forward: Vector3) -> void:
	var player: CharacterBody3D = _host.player
	# An intact table's collider is a static child; the owning prop takes the hit, as bullets do.
	var body := hit
	var owner := body.get_parent() as Node3D
	if not body.has_method("take_melee_hit") and owner != null and owner.has_method("take_melee_hit"):
		body = owner
	if body.has_method("take_melee_hit"):
		body.call("take_melee_hit", KICK_OBJECT_DAMAGE, body.global_position, forward)
		SFX.play(player, _hit_event(body), body.global_position)
	if body is RigidBody3D and not (body as RigidBody3D).freeze:
		_throw(body as RigidBody3D, player.global_position)


static func _hit_event(body: Node3D) -> StringName:
	var material := str(body.call("get_projectile_material", -1)) if body.has_method("get_projectile_material") else "wood"
	return HIT_EVENTS.get(material, &"hit_wood")


# Flings a loose item away from the character; heavy ones barely move.
static func _throw(body: RigidBody3D, from: Vector3) -> void:
	var away := body.global_position - from
	away.y = 0.0
	if away.length_squared() < 0.0001:
		return
	var speed := minf(KICK_IMPULSE / maxf(body.mass, 0.01), KICK_MAX_SPEED) # No floor: heavy items must not be flung at a minimum speed.
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
