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
var _material: ShaderMaterial
var _fade := 1.0
var _shape := SphereShape3D.new()
static var _mesh: ArrayMesh


func configure(origin: Vector3, radius: float, wave_speed: float, damage_to_player: float, damage_to_objects: float, wave_source: Node3D, tint: Color) -> void:
	max_radius = radius
	speed = wave_speed
	player_damage = damage_to_player
	object_damage = damage_to_objects
	source = wave_source
	color = tint
	global_position = origin


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = preload("res://game/features/infected/ground_shockwave.gdshader")
	_material.set_shader_parameter("tint", color)
	# Slam wave lifts the floor; the Horde's summoning pulse barely ripples it.
	_material.set_shader_parameter("lift", 0.6 if player_damage > 0.0 or object_damage > 0.0 else 0.08)
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = _annulus()
	_ring.material_override = _material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position.y = 0.03
	# Only the floor plane scales; the shader keeps the crest height in metres.
	_ring.scale = Vector3(max_radius, 1.0, max_radius)
	add_child(_ring)
	if player_damage > 0.0 or object_damage > 0.0:
		add_child(_dust())
	_update_ring()


# Unit-radius flat ring mesh, built once and shared; the vertex shader raises it.
static func _annulus() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var rings := 28
	var segments := 72
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in rings + 1:
		var r := 0.02 + 0.98 * float(i) / rings
		for j in segments + 1:
			var a := TAU * float(j) / segments
			vertices.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	for i in rings:
		for j in segments:
			var k := i * (segments + 1) + j
			indices.append_array([k, k + 1, k + segments + 1, k + 1, k + segments + 2, k + segments + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Displaced vertices leave the flat bounds, so keep the node from being culled.
	_mesh.custom_aabb = AABB(Vector3(-1, -0.2, -1), Vector3(2, 3, 2))
	return _mesh


# One burst of rubble kicked up at the impact point.
func _dust() -> CPUParticles3D:
	var dust := CPUParticles3D.new()
	dust.name = "Dust"
	dust.amount = 24
	dust.one_shot = true
	dust.explosiveness = 1.0
	dust.lifetime = 0.7
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	dust.emission_ring_axis = Vector3.UP
	dust.emission_ring_radius = 1.2
	dust.emission_ring_inner_radius = 0.4
	dust.emission_ring_height = 0.1
	dust.direction = Vector3.UP
	dust.spread = 55.0
	dust.initial_velocity_min = 2.0
	dust.initial_velocity_max = 5.0
	dust.gravity = Vector3(0, -9.0, 0)
	dust.scale_amount_min = 0.5
	dust.scale_amount_max = 1.4
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color.darkened(0.25)
	mesh.material = material
	dust.mesh = mesh
	dust.emitting = true
	return dust


func _physics_process(delta: float) -> void:
	_radius = minf(max_radius, _radius + speed * delta)
	_update_ring()
	if player_damage > 0.0 or object_damage > 0.0:
		_strike_passed_bodies()
	if _radius >= max_radius:
		set_physics_process(false)
		var tween := create_tween()
		tween.tween_method(_set_fade, _fade, 0.0, 0.25)
		tween.tween_callback(queue_free)


func _update_ring() -> void:
	var progress := _radius / maxf(max_radius, 0.01)
	_material.set_shader_parameter("front", progress)
	_material.set_shader_parameter("band", 1.8 / maxf(max_radius, 0.01))
	_set_fade(1.0 - 0.6 * progress if _radius < max_radius else _fade)


func _set_fade(value: float) -> void:
	_fade = value
	_material.set_shader_parameter("fade", value)


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
	# Furniture is not cover, but it must not hide the wall further along the ray.
	# Exclude whole bodies without moving the origin past any unchecked geometry.
	while not hit.is_empty():
		var collider := hit.get("collider") as CollisionObject3D
		if collider == null:
			return false
		var own_part := body.is_ancestor_of(collider) or (is_instance_valid(source) and source.is_ancestor_of(collider))
		if collider is StaticBody3D and not own_part:
			return true
		excluded.append(collider.get_rid())
		query.exclude = excluded
		hit = get_world_3d().direct_space_state.intersect_ray(query)
	return false


func _strike(collider: Node3D, shape_index: int, offset: Vector3) -> void:
	if collider.is_in_group("infected"):
		return
	var flat := Vector3(offset.x, 0.0, offset.z)
	var falloff := 1.0 - 0.55 * clampf(flat.length() / maxf(max_radius, 0.01), 0.0, 1.0)
	var direction := (flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD) + Vector3.UP * 0.35
	direction = direction.normalized()
	if collider.is_in_group("player"):
		if player_damage > 0.0 and collider.has_method("take_damage"):
			preload("res://game/features/infected/enemy_interaction_rules.gd").damage(collider, player_damage * falloff, true)
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
