extends RefCounted
const SPARKS := preload("res://game/presentation/office_floor/electric_sparks.gd")

# Shared point-blank blast response for extinguisher and future explosions.
static func detonate(host: Node3D, location: Vector3, radius: float = 5.0) -> void:
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
	var world := host.get_tree().current_scene
	if world == null:
		return
	var cloud := GPUParticles3D.new()
	cloud.name = "ExtinguisherSmoke"
	cloud.amount = 85
	cloud.lifetime = 2.3
	cloud.one_shot = true
	cloud.explosiveness = 0.45
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.3
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 1.0
	process.initial_velocity_max = 3.0
	process.gravity = Vector3(0, 0.18, 0)
	cloud.process_material = process
	var puff := SphereMesh.new()
	puff.radius = 0.19
	puff.height = 0.38
	var smoke_material := StandardMaterial3D.new()
	smoke_material.albedo_color = Color(0.74, 0.77, 0.72, 0.32)
	smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = smoke_material
	cloud.draw_pass_1 = puff
	world.add_child(cloud)
	cloud.global_position = location
	cloud.emitting = true
	world.get_tree().create_timer(4.0).timeout.connect(cloud.queue_free)
