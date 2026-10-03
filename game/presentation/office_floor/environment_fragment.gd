extends RigidBody3D
## A loose piece of a destroyed environment object.
##
## Layers: pieces live on physics layer 3 (value 4) so bullets and grenades can
## hit them, but characters never collide with them. They rest on the floor,
## walls and props (mask 3) and ignore the player and infected explicitly.
## Pieces shrink away when their lifetime ends or the debris budget is full.

const BALANCE = preload("res://game/features/combat/public/projectile_balance.gd")
const DEBRIS = preload("res://game/presentation/office_floor/debris_lifecycle.gd")
const GROUP := "fallen_environment_fragment"
const HIT_LAYER := 4
const WORLD_MASK := 3
const MAX_FRAGMENTS := 40
const KICK_COOLDOWN := 0.8

static var _surface: PhysicsMaterial

var source: WeakRef
var piece_name := ""
var stage_index := -1
var kickable := false
var _kick_cooldown := 0.0
var _age := 0.0
var _piece_health := 55.0


func _ready() -> void:
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
	# Only kickable pieces poll for the player; all others cost no script time.
	set_physics_process(kickable)
	add_to_group(GROUP)
	var tween := create_tween()
	tween.tween_interval(32.0 if kickable else 14.0)
	tween.tween_callback(expire)
	_enforce_budget()


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
	DEBRIS.fade_free(self)


func expire_fast() -> void:
	DEBRIS.fade_free(self, DEBRIS.FAST_FADE_SECONDS)


# Pieces are contactless for characters: pairs with them would otherwise exist
# because this body scans the characters' layers.
func _ignore_characters() -> void:
	var tree := get_tree()
	for group in ["player", "infected"]:
		for node in tree.get_nodes_in_group(group):
			if node is CollisionObject3D:
				add_collision_exception_with(node)


func _enforce_budget() -> void:
	var live: Array[Node] = []
	for piece in get_tree().get_nodes_in_group(GROUP):
		if not DEBRIS.is_fading(piece) and not piece.is_queued_for_deletion():
			live.append(piece)
	while live.size() > MAX_FRAGMENTS:
		(live.pop_front() as Node).call("expire_fast")


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
