extends RigidBody3D
const IMPACT_SOUND := preload("res://game/presentation/office_floor/impact_sound_watcher.gd")
## A loose piece of a destroyed environment object.
##
## Layers: pieces live on physics layer 3 (value 4) so bullets and grenades can
## hit them, but characters never collide with them. They rest on the floor,
## walls and props (mask 3) and ignore the player and infected explicitly.
## Pieces shrink away when their lifetime ends or the debris budget is full.

const BALANCE = preload("res://game/features/combat/public/projectile_balance.gd")
const DEBRIS = preload("res://game/presentation/office_floor/debris_lifecycle.gd")
const QUALITY = preload("res://game/core/vfx/public/destruction_quality.gd")
const GROUP := "fallen_environment_fragment"
# Infected spawned after this piece skip contact with it as well.
const CONTACTLESS_GROUP := "contactless_debris"
const HIT_LAYER := 4
const WORLD_MASK := 3
# Large pieces (a tabletop, its pedestal, a leg) also collide with each other on this extra layer,
# so a fallen top rests on its pedestal instead of passing through it. Characters never use it.
const PIECE_LAYER := 16
const PIECE_MIN_EDGE := 0.3
# A piece at least this tall and this many times taller than wide falls over instead of standing.
const TOPPLE_MIN_HEIGHT := 0.5
const TOPPLE_SLENDERNESS := 1.8
const TOPPLE_SPEED := 4.0
# Pieces that start touching (a top resting on a leg) are pushed apart; this caps how fast they may leave.
const MAX_PIECE_SPEED := 6.0
const TOPPLE_RETRIES := 3
const TOPPLE_RETRY_DELAY := 0.7
const KICK_COOLDOWN := 0.8
# A piece that is allowed to stay loose looks again after this long.
const LOOSE_RECHECK_SECONDS := 4.0
# Highest lowest point of a resting piece that still counts as lying on the floor.
const BAKE_MAX_HEIGHT := 0.15
# Top of the base floor (see FLOOR_TOP in environment_prop.gd). Nothing in the level lies lower.
const FLOOR_TOP := 0.0135
# A piece may overlap the floor by this much before it is lifted back; the solver needs a little slack.
const FLOOR_SLACK := 0.004

static var _surface: PhysicsMaterial

var source: WeakRef
var piece_name := ""
var stage_index := -1
var kickable := false
# A piece with a next stage keeps its body while it rests, so a later hit can break it further.
var breakable := false
var _kick_cooldown := 0.0
var _age := 0.0
var rest_time := 0.0
var _piece_health := 55.0
var pool_owner: Node
var _runtime: Node
var _expiry: Tween
var _half_extents := Vector3.ZERO
var _capped := false


func _ready() -> void:
	_age = 0.0
	rest_time = 0.0
	_kick_cooldown = 0.0
	_piece_health = 55.0
	_half_extents = Vector3.ZERO
	collision_layer = HIT_LAYER
	collision_mask = WORLD_MASK
	if _surface == null:
		_surface = PhysicsMaterial.new()
		_surface.friction = 0.7
		_surface.bounce = 0.22
	physics_material_override = _surface
	linear_damp = 0.35
	angular_damp = 0.9
	can_sleep = true
	_ignore_characters()
	var watcher := get_node_or_null("ImpactSound")
	if watcher == null:
		IMPACT_SOUND.watch(self, -6.0, &"fall_debris")
	else:
		watcher.call("reset_fragment")
	# Only kickable pieces poll for the player; all others cost no script time.
	set_physics_process(kickable)
	add_to_group(GROUP)
	add_to_group(CONTACTLESS_GROUP)
	_expiry = create_tween()
	_expiry.tween_interval(32.0 if kickable else 14.0)
	_expiry.tween_callback(expire)
	call_deferred("_register_budget")


## Large non-glass pieces keep their volume against each other.
func enable_piece_contacts() -> void:
	collision_layer |= PIECE_LAYER
	collision_mask |= PIECE_LAYER
	_capped = true


## A tall slender piece left standing (a pedestal, a leg) is pushed over, away from the hit.
func topple_from(size: Vector3, hit_position: Vector3, direction: Vector3) -> void:
	var width := maxf(size.x, size.z)
	if size.y < TOPPLE_MIN_HEIGHT or size.y < width * TOPPLE_SLENDERNESS:
		return
	var away := global_position - hit_position
	away.y = 0.0
	if away.length_squared() < 0.0004:
		away = Vector3(direction.x, 0.0, direction.z)
	if away.length_squared() < 0.0004:
		away = Vector3.RIGHT
	_push_over(away.normalized(), size.y, 1.0, TOPPLE_RETRIES)


# A piece pinned under a heavy top can survive the first push, so it is pushed again, harder, while it still stands.
func _push_over(away: Vector3, height: float, scale: float, retries: int) -> void:
	sleeping = false
	apply_impulse(away * mass * TOPPLE_SPEED * scale, Vector3.UP * height * 0.4)
	if retries <= 0 or not is_inside_tree():
		return
	await get_tree().create_timer(TOPPLE_RETRY_DELAY).timeout
	if is_inside_tree() and not is_queued_for_deletion() and global_basis.y.angle_to(Vector3.UP) < deg_to_rad(30.0):
		_push_over(away, height, scale * 1.3, retries - 1)


# A thin panel landing fast on its edge can be pushed a few centimetres into the floor before the
# solver pushes it out again, so its wall is seen cutting through the tiles. The lowest point of its
# box is kept at the floor surface: the piece is lifted and stops falling.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _capped and state.linear_velocity.length() > MAX_PIECE_SPEED:
		state.linear_velocity = state.linear_velocity.limit_length(MAX_PIECE_SPEED)
	if _half_extents == Vector3.ZERO:
		for child in get_children():
			if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
				_half_extents = ((child as CollisionShape3D).shape as BoxShape3D).size * 0.5
				break
		if _half_extents == Vector3.ZERO:
			return
	var transform := state.transform
	var basis := transform.basis
	var depth := absf(basis.x.y) * _half_extents.x + absf(basis.y.y) * _half_extents.y + absf(basis.z.y) * _half_extents.z
	var deficit := FLOOR_TOP - FLOOR_SLACK - (transform.origin.y - depth)
	if deficit <= 0.0:
		return
	transform.origin.y += deficit
	state.transform = transform
	if state.linear_velocity.y < 0.0:
		state.linear_velocity.y = 0.0


func _register_budget() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or DEBRIS.is_fading(self):
		return
	_runtime = DEBRIS.runtime_for(get_parent())
	_runtime.register(self)


func _physics_process(delta: float) -> void:
	_age += delta
	_kick_cooldown -= delta
	if _age < 0.6 or _kick_cooldown > 0.0:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var offset := global_position - player.global_position
	if absf(offset.y) > 1.4 or Vector2(offset.x, offset.z).length_squared() > 0.7:
		return
	_kick_cooldown = KICK_COOLDOWN
	sleeping = false
	var away := Vector3(offset.x, 0.0, offset.z).normalized()
	apply_central_impulse((away + Vector3.UP * 0.25) * minf(mass * 1.7, 0.9))


func expire() -> void:
	_leave_floor(DEBRIS.FADE_SECONDS, false)


# The debris budget is full: even a breakable piece has to go.
func expire_fast() -> void:
	_leave_floor(DEBRIS.FAST_FADE_SECONDS, true)


# A resting piece with a next stage stays until the budget needs it, so a later hit can break it further.
# Every other model piece bakes into the floor; one still moving, lodged in a frame or propped up is
# dropped onto the floor under it first, so no piece of a destroyed object just vanishes.
func _leave_floor(seconds: float, budget_full: bool) -> void:
	if DEBRIS.is_fading(self):
		return
	if breakable and not budget_full and _lies_on_floor():
		return
	if not budget_full and _stays_loose():
		_expiry = create_tween()
		_expiry.tween_interval(LOOSE_RECHECK_SECONDS)
		_expiry.tween_callback(expire)
		return
	if pool_owner == null and is_instance_valid(_runtime):
		_runtime.call("bake", self)
	else:
		DEBRIS.fade_free(self, seconds)


# High keeps every model piece until the budget needs it; Medium keeps the ones near the player.
func _stays_loose() -> bool:
	if pool_owner != null:
		return false
	if QUALITY.pieces_persist():
		return true
	var near := QUALITY.keep_near()
	if near <= 0.0 or not is_inside_tree():
		return false
	var player := get_tree().get_first_node_in_group("player") as Node3D
	return player != null and global_position.distance_to(player.global_position) <= near


# Asleep with the lowest point of its model at floor level.
func _lies_on_floor() -> bool:
	if not sleeping:
		return false
	for child in get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			var box: AABB = (child as MeshInstance3D).global_transform * (child as MeshInstance3D).get_aabb()
			return box.position.y < BAKE_MAX_HEIGHT
	return global_position.y < BAKE_MAX_HEIGHT


# Pieces are contactless for characters: pairs with them would otherwise exist
# because this body scans the characters' layers.
func _ignore_characters() -> void:
	var tree := get_tree()
	for group in ["player", "infected"]:
		for node in tree.get_nodes_in_group(group):
			if node is CollisionObject3D:
				add_collision_exception_with(node)


func retire_from_budget() -> void:
	if _expiry != null:
		_expiry.kill()
	if is_instance_valid(_runtime):
		_runtime.unregister(self)


func recycle_chunk() -> void:
	if is_instance_valid(pool_owner):
		pool_owner.recycle(self)
	else:
		queue_free()


func _exit_tree() -> void:
	retire_from_budget()


# Debris absorbs weak shots but lets stronger bullets continue through it.
func take_projectile_hit(damage: float, hit_position: Vector3, _normal: Vector3, direction: Vector3, weapon: String) -> bool:
	if DEBRIS.is_fading(self):
		return false
	_piece_health -= BALANCE.object_damage(damage, weapon, "large")
	if _piece_health > 0.0:
		sleeping = false
		apply_central_impulse(direction.normalized() * 0.35)
		return false
	_piece_health = 55.0
	var piece_owner: Node = null
	if source != null:
		piece_owner = source.get_ref() as Node
	if piece_owner != null and piece_owner.has_method("hit_environment_fragment"):
		piece_owner.call("hit_environment_fragment", self, hit_position, direction)
	else:
		sleeping = false
		apply_central_impulse(direction.normalized() * 0.5)
	return false


func get_projectile_material(_shape_index: int = -1) -> String:
	return "light"


func take_melee_hit(damage: float, hit_position: Vector3, direction: Vector3) -> void:
	take_projectile_hit(damage, hit_position, Vector3.ZERO, direction, "MELEE")
