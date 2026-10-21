extends RefCounted
const SPARKS := preload("res://game/presentation/office_floor/electric_sparks.gd")
const GRENADE := preload("res://game/features/combat/public/grenade_explosion.gd")

# Extinguisher strength lives here; prop damage and falloff come from the grenade blast path.
# The radius matches the powder cloud (extinguisher_hit_fx cloud_radius) and is well under a grenade's 5.5 m.
const EXTINGUISHER_RADIUS := 3.0
const CREATURE_DAMAGE := 14.0
const STUN_BASE := 3.0
const STUN_FALLOFF := 2.0
const SHELTER_LIFT := 0.25

# Shared point-blank blast response for extinguisher and future explosions.
static func detonate(host: Node3D, location: Vector3, radius: float = EXTINGUISHER_RADIUS, show_visuals: bool = true) -> void:
	if show_visuals:
		smoke(host, location)
		SPARKS.spawn(host, location, true)
	for group in ["player", "infected"]:
		for victim in host.get_tree().get_nodes_in_group(group):
			if not victim is Node3D:
				continue
			var distance := (victim as Node3D).global_position.distance_to(location)
			if distance >= radius:
				continue
			var force := 1.0 - distance / radius
			if victim.has_method("take_damage"):
				victim.call("take_damage", CREATURE_DAMAGE * force)
			if victim.has_method("apply_blast_stun"):
				victim.call("apply_blast_stun", STUN_BASE + STUN_FALLOFF * force, force)
	_damage_objects(host, location, radius)


# Props and glass take the grenade hit (shelter, shape, falloff, push) so they break in stages.
static func _damage_objects(host: Node3D, location: Vector3, radius: float) -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	query.shape = sphere
	query.transform.origin = location
	query.collision_mask = 7
	var world := host.get_world_3d()
	var hit_ids := {}
	for hit in GRENADE.blast_hits(world.direct_space_state, query):
		var body := hit.get("collider") as Node3D
		if body == null or body == host or hit_ids.has(body.get_instance_id()):
			continue
		hit_ids[body.get_instance_id()] = true
		if not body.has_method("take_projectile_hit") and not body.has_method("take_projectile_hit_at_shape") or _is_creature(body):
			continue
		if GRENADE.is_sheltered(world, location + Vector3.UP * SHELTER_LIFT, body):
			continue
		var shape := int(hit.get("shape", -1))
		var distance := GRENADE.distance_to_shape(body, shape, location, body.global_position)
		var factor := pow(1.0 - clampf(distance / radius, 0.0, 1.0), 1.15)
		var direction := (body.global_position - location).normalized()
		if direction.length_squared() < 0.01:
			direction = Vector3.UP
		GRENADE.hit_object(body, shape, location, direction, factor)
		GRENADE.push_body(body, direction, factor)


# Enemies and the player are hit through their own damage path above.
static func _is_creature(node: Node) -> bool:
	var current := node
	while current != null:
		if current.is_in_group("player") or current.is_in_group("infected"):
			return true
		current = current.get_parent()
	return false


static func smoke(host: Node3D, location: Vector3) -> void:
	var world := host.get("effects_root") as Node3D
	if not is_instance_valid(world):
		return
	var cloud := GPUParticles3D.new()
	cloud.name = "ExtinguisherSmoke"
	cloud.amount = SMOKE_PUFFS
	cloud.lifetime = 2.3
	cloud.one_shot = true
	cloud.explosiveness = 0.45
	cloud.process_material = _smoke_process()
	cloud.draw_pass_1 = _smoke_puff()
	world.add_child(cloud)
	cloud.global_position = location
	cloud.emitting = true
	world.get_tree().create_timer(4.0).timeout.connect(cloud.queue_free)


const SMOKE_PUFFS := 48
static var _smoke_process_material: ParticleProcessMaterial
static var _smoke_mesh: SphereMesh


# Built once: the smoke never varies, so each extinguisher only spawns the node.
static func _smoke_process() -> ParticleProcessMaterial:
	if _smoke_process_material == null:
		_smoke_process_material = ParticleProcessMaterial.new()
		_smoke_process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		_smoke_process_material.emission_sphere_radius = 0.3
		_smoke_process_material.direction = Vector3.UP
		_smoke_process_material.spread = 180.0
		_smoke_process_material.initial_velocity_min = 1.0
		_smoke_process_material.initial_velocity_max = 3.0
		_smoke_process_material.gravity = Vector3(0, 0.18, 0)
	return _smoke_process_material


static func _smoke_puff() -> SphereMesh:
	if _smoke_mesh == null:
		_smoke_mesh = SphereMesh.new()
		_smoke_mesh.radius = 0.19
		_smoke_mesh.height = 0.38
		var smoke_material := StandardMaterial3D.new()
		smoke_material.albedo_color = Color(0.74, 0.77, 0.72, 0.32)
		smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smoke_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_smoke_mesh.material = smoke_material
	return _smoke_mesh
