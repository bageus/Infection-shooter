extends Node3D
## Expanding ground ring (ADR-0016). With damage it is the Colossus slam wave:
## as the front passes, the player is hurt, breakable objects are hit like a
## grenade and loose bodies are thrown outward. Without damage it is only the
## Horde's summoning pulse. Infected are never hurt by either.

const BULLET_MASK := 7
const MAX_HEIGHT := 2.4

var max_radius := 5.5
var speed := 9.0
var player_damage := 0.0
var object_damage := 0.0
var impulse := 4.0
var source: Node3D
var color := Color(0.62, 0.5, 0.38, 0.75)

var _radius := 0.2
var _hit := {}
var _ring: MeshInstance3D
var _material: StandardMaterial3D
var _shape := SphereShape3D.new()


func configure(origin: Vector3, radius: float, wave_speed: float, damage_to_player: float, damage_to_objects: float, wave_source: Node3D, tint: Color) -> void:
	max_radius = radius
	speed = wave_speed
	player_damage = damage_to_player
	object_damage = damage_to_objects
	source = wave_source
	color = tint
	global_position = origin


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = color
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 6
	torus.material = _material
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = torus
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position.y = 0.06
	add_child(_ring)
	_update_ring()


func _physics_process(delta: float) -> void:
	_radius = minf(max_radius, _radius + speed * delta)
	_update_ring()
	if player_damage > 0.0 or object_damage > 0.0:
		_strike_passed_bodies()
	if _radius >= max_radius:
		set_physics_process(false)
		var tween := create_tween()
		tween.tween_property(_material, "albedo_color:a", 0.0, 0.25)
		tween.tween_callback(queue_free)


func _update_ring() -> void:
	var fade := 1.0 - 0.6 * (_radius / maxf(max_radius, 0.01))
	_ring.scale = Vector3(_radius, 0.35 + 0.4 * fade, _radius)
	_material.albedo_color = Color(color.r, color.g, color.b, color.a * fade)


func _strike_passed_bodies() -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	_shape.radius = _radius
	query.shape = _shape
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.collision_mask = BULLET_MASK
	if is_instance_valid(source) and source is CollisionObject3D:
		query.exclude = [(source as CollisionObject3D).get_rid()]
	for hit in space.intersect_shape(query, 128):
		var collider := hit.get("collider") as Node3D
		if collider == null or _hit.has(collider.get_instance_id()):
			continue
		var offset := collider.global_position - global_position
		if offset.y > MAX_HEIGHT or Vector2(offset.x, offset.z).length() > _radius + 0.3:
			continue
		_hit[collider.get_instance_id()] = true
		if _sheltered(collider):
			continue
		_strike(collider, int(hit.get("shape", -1)), offset)


# The ground wave does not pass through walls.
func _sheltered(body: Node3D) -> bool:
	var target := body.global_position + Vector3.UP * 0.4
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.4, target, 1)
	var excluded: Array[RID] = []
	if body is CollisionObject3D:
		excluded.append((body as CollisionObject3D).get_rid())
	if is_instance_valid(source) and source is CollisionObject3D:
		excluded.append((source as CollisionObject3D).get_rid())
	query.exclude = excluded
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.get("collider") is StaticBody3D


func _strike(collider: Node3D, shape_index: int, offset: Vector3) -> void:
	if collider.is_in_group("infected"):
		return
	var flat := Vector3(offset.x, 0.0, offset.z)
	var falloff := 1.0 - 0.55 * clampf(flat.length() / maxf(max_radius, 0.01), 0.0, 1.0)
	var direction := (flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD) + Vector3.UP * 0.35
	direction = direction.normalized()
	if collider.is_in_group("player"):
		if player_damage > 0.0 and collider.has_method("take_damage"):
			collider.call("take_damage", player_damage * falloff)
		return
	if object_damage > 0.0:
		if collider.has_method("take_projectile_hit_at_shape"):
			collider.call("take_projectile_hit_at_shape", object_damage * falloff, collider.global_position, -direction, direction, "GRENADE", shape_index)
		elif collider.has_method("take_projectile_hit"):
			collider.call("take_projectile_hit", object_damage * falloff, collider.global_position, -direction, direction, "GRENADE")
	if is_instance_valid(collider) and collider is RigidBody3D and not (collider as RigidBody3D).freeze:
		var body := collider as RigidBody3D
		body.sleeping = false
		body.apply_central_impulse(direction * impulse * falloff * clampf(body.mass, 0.3, 12.0))
