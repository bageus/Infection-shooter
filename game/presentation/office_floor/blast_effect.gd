extends RefCounted
const SPARKS := preload("res://game/presentation/office_floor/electric_sparks.gd")

# Shared point-blank blast response for extinguisher and future explosions.
static func detonate(host: Node3D, location: Vector3, radius: float = 5.0, show_visuals: bool = true) -> void:
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
				victim.call("take_damage", 14.0 * force)
			if victim.has_method("apply_blast_stun"):
				victim.call("apply_blast_stun", 3.0 + 2.0 * force, force)


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
