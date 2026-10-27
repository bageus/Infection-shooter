extends Node3D
## Scene-local, bounded exit particles. No lights or gameplay state.
const BLOOD_LEVEL := preload("res://game/core/vfx/public/blood_level.gd")
const MAX_ACTIVE := 24
var _blood: SphereMesh
var _sparks: SphereMesh


static func spawn(container: Node3D, point: Vector3, direction: Vector3, material: String, energy: float) -> void:
	if not is_instance_valid(container) or not container.is_inside_tree():
		return
	var runtime := container.get_node_or_null("CombatPenetrationFx")
	if runtime == null:
		runtime = load("res://game/features/combat/penetration_burst.gd").new()
		runtime.name = "CombatPenetrationFx"
		container.add_child(runtime)
	runtime.emit_burst(point, direction, material, energy)


func emit_burst(point: Vector3, direction: Vector3, material: String, energy: float) -> void:
	if get_child_count() >= MAX_ACTIVE:
		return
	var blood := material == "flesh"
	var strength := clampf(energy / 110.0, 0.0, 1.0)
	var particles := GPUParticles3D.new()
	particles.name = "ExitBlood" if blood else "ExitSparks"
	particles.set_meta("exit_material", material)
	particles.amount = roundi(lerpf(8, 32, strength)) if blood else roundi(lerpf(4, 12, strength))
	particles.lifetime = 0.55 if blood else 0.24
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
	var process := ParticleProcessMaterial.new()
	process.direction = direction.normalized()
	process.spread = lerpf(18, 32, strength)
	process.initial_velocity_min = lerpf(1.0, 2.8, strength)
	process.initial_velocity_max = lerpf(2.5, 7.0, strength) if blood else lerpf(1.8, 4.0, strength)
	process.gravity = Vector3(0, -9.8, 0)
	process.scale_min = 0.5
	process.scale_max = 1.2 if blood else 0.8
	particles.process_material = process
	particles.draw_pass_1 = _mesh(blood)
	add_child(particles)
	particles.global_position = point + direction * 0.015
	particles.emitting = true
	var ref: WeakRef = weakref(particles)
	get_tree().create_timer(0.85).timeout.connect(func() -> void:
		var live := ref.get_ref() as Node
		if live != null:
			live.queue_free())


func _mesh(blood: bool) -> SphereMesh:
	if (blood and _blood != null) or (not blood and _sparks != null):
		return _blood if blood else _sparks
	var mesh := SphereMesh.new()
	mesh.radius = 0.018 if blood else 0.012
	mesh.height = mesh.radius * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.albedo_color = BLOOD_LEVEL.color() if blood else Color(0.65, 0.32, 0.06)
	material.roughness = 0.2
	if not blood:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		material.emission = Color(0.7, 0.28, 0.03)
		material.emission_energy_multiplier = 0.65
	mesh.material = material
	if blood:
		_blood = mesh
	else:
		_sparks = mesh
	return mesh
