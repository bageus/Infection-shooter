extends RigidBody3D

var source: WeakRef
var piece_name := ""
var stage_index := -1
var kickable := false
var _kick_cooldown := 0.0
var _age := 0.0


func _ready() -> void:
	# Only the floor has layer 2. Player and walls stay on layer 1.
	collision_layer = 0
	collision_mask = 2
	add_to_group("fallen_environment_fragment")
	var lifetime := 32.0 if kickable else 14.0
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
	var fragments := get_tree().get_nodes_in_group("fallen_environment_fragment")
	if fragments.size() > 40:
		fragments[0].queue_free()


func _physics_process(delta: float) -> void:
	_age += delta
	_kick_cooldown -= delta
	if not kickable or _age < 0.6 or _kick_cooldown > 0.0:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var offset := global_position - player.global_position
	if absf(offset.y) > 1.4 or Vector2(offset.x, offset.z).length_squared() > 0.7:
		return
	_kick_cooldown = 0.8
	sleeping = false
	var away := Vector3(offset.x, 0.0, offset.z).normalized()
	apply_central_impulse((away + Vector3.UP * 0.25) * minf(mass * 1.7, 0.9))


func take_projectile_hit(_damage: float, hit_position: Vector3, _normal: Vector3, direction: Vector3, _weapon: String) -> bool:
	var owner := source.get_ref() if source != null else null
	if owner != null and owner.has_method("hit_environment_fragment"):
		owner.call("hit_environment_fragment", self, hit_position, direction)
	else:
		apply_central_impulse(direction.normalized() * 0.5)
	return false


func take_melee_hit(damage: float, hit_position: Vector3, direction: Vector3) -> void:
	take_projectile_hit(damage, hit_position, Vector3.ZERO, direction, "MELEE")
