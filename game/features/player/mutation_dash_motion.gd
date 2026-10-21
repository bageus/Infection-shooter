extends RefCounted
## Six-metre dash: scenery stops it, while loose objects, debris and enemies on its path are shoved aside.
## Shove momentum matches a rifle hit (bullet_push.gd); a light item is capped at its top speed.
const SHOVE_MOMENTUM := 9.0
const SHOVE_MAX_SPEED := 3.2
## Debris pieces live on the hit layer 4 and the piece layer 16 (environment_fragment.gd).
const DEBRIS_MASK := 20
const DEBRIS_GROUP := &"contactless_debris"
const DEBRIS_RADIUS := 0.9
var active := false
var remaining := 0.0
var _mask := 0
var _before := Vector3.ZERO
var _shoved := {}


func begin(player: CharacterBody3D) -> void:
	if active:
		return
	active = true
	remaining = 6.0
	_mask = player.collision_mask
	_shoved.clear()
	player.collision_mask &= ~2
	player._roll_direction = -player.aim_pivot.global_basis.z
	player._roll_direction.y = 0.0
	player._roll_direction = player._roll_direction.normalized()
	player._roll_remaining = 0.4
	player._roll_pace = 15.0


func before_move(player: CharacterBody3D, delta: float) -> void:
	_before = player.global_position
	if active:
		player._roll_pace = minf(player._roll_pace, remaining / maxf(delta, 0.0001))


func after_move(player: CharacterBody3D) -> void:
	if not active:
		return
	remaining = maxf(0.0, remaining - Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(_before.x, _before.z)))
	for index in player.get_slide_collision_count():
		var collision := player.get_slide_collision(index)
		var collider := collision.get_collider()
		if collider is RigidBody3D:
			_shove(collider, player._roll_direction, collision.get_position())
		elif collision.get_normal().dot(player._roll_direction) < -0.1:
			player._roll_pace = 0.0
	_shove_debris(player)
	if player._roll_remaining <= 0.0:
		player.velocity.x = 0.0
		player.velocity.z = 0.0
		player.collision_mask = _mask
		active = false


# Each body is shoved once per dash, with the momentum a rifle hit would give it.
func _shove(body: RigidBody3D, direction: Vector3, hit_position: Vector3) -> void:
	var id := body.get_instance_id()
	if body.freeze or _shoved.has(id):
		return
	_shoved[id] = true
	body.sleeping = false
	var impulse := minf(SHOVE_MOMENTUM, SHOVE_MAX_SPEED * body.mass)
	body.apply_impulse(direction.normalized() * impulse, hit_position - body.global_position)


func _shove_debris(player: CharacterBody3D) -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = DEBRIS_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), player.global_position + Vector3.UP * 0.5)
	query.collision_mask = DEBRIS_MASK
	query.exclude = [player.get_rid()]
	for hit in player.get_world_3d().direct_space_state.intersect_shape(query, 16):
		var body := hit["collider"] as Object
		if body is RigidBody3D and body.is_in_group(DEBRIS_GROUP):
			_shove(body, player._roll_direction, (body as Node3D).global_position)
