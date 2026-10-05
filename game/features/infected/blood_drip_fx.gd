extends RefCounted
## Short-lived blood particles for wounds, stumps and severed parts
## (ADR-0017). Purely visual; decals on the floor come from the blood events
## the infected and its parts emit.

const GROUP := "infected_blood_fx"
const MAX_ACTIVE := 24

static var _droplet: SphereMesh
static var _material: StandardMaterial3D


# Continuous dripping/spurting from `parent` (local `offset`) for `seconds`.
static func bleed(parent: Node3D, offset: Vector3, direction: Vector3, seconds: float, strength: float) -> GPUParticles3D:
	var particles := _make(parent, roundi(lerpf(18.0, 46.0, clampf(strength, 0.0, 1.0))), 0.9, false)
	if particles == null:
		return null
	particles.position = offset
	var process := particles.process_material as ParticleProcessMaterial
	process.direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.DOWN
	process.spread = 28.0
	process.initial_velocity_min = 0.6 * strength
	process.initial_velocity_max = 2.4 * strength
	particles.emitting = true
	var tree := parent.get_tree()
	var ref: WeakRef = weakref(particles)
	tree.create_timer(seconds).timeout.connect(func() -> void:
		var live := ref.get_ref() as GPUParticles3D
		if live != null:
			live.emitting = false)
	tree.create_timer(seconds + particles.lifetime + 0.2).timeout.connect(func() -> void:
		var live := ref.get_ref() as Node
		if live != null:
			live.queue_free())
	return particles


# One burst of droplets flying along `direction` (a bullet exit spray).
static func spray(parent: Node3D, world_position: Vector3, direction: Vector3, amount: int, force: float) -> void:
	var particles := _make(parent, amount, 0.7, true)
	if particles == null:
		return
	particles.global_position = world_position
	var process := particles.process_material as ParticleProcessMaterial
	process.direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.UP
	process.spread = 38.0
	process.initial_velocity_min = 1.5 * force
	process.initial_velocity_max = 4.5 * force
	particles.emitting = true
	var ref: WeakRef = weakref(particles)
	parent.get_tree().create_timer(particles.lifetime + 0.3).timeout.connect(func() -> void:
		var live := ref.get_ref() as Node
		if live != null:
			live.queue_free())


static var _active := 0


static func _make(parent: Node3D, amount: int, lifetime: float, one_shot: bool) -> GPUParticles3D:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	# A running count instead of scanning the group on every hit.
	if _active >= MAX_ACTIVE:
		return null
	if _droplet == null:
		_material = StandardMaterial3D.new()
		_material.albedo_color = Color(0.36, 0.01, 0.01)
		_material.roughness = 0.2
		_material.metallic_specular = 0.7
		_droplet = SphereMesh.new()
		_droplet.radius = 0.018
		_droplet.height = 0.036
		_droplet.radial_segments = 6
		_droplet.rings = 3
		_droplet.material = _material
	var particles := GPUParticles3D.new()
	particles.name = "BloodDrops"
	particles.add_to_group(GROUP)
	_active += 1
	particles.tree_exiting.connect(func() -> void: _active -= 1)
	particles.amount = maxi(1, amount)
	particles.lifetime = lifetime
	particles.one_shot = one_shot
	particles.explosiveness = 0.85 if one_shot else 0.0
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.gravity = Vector3(0.0, -9.8, 0.0)
	process.scale_min = 0.5
	process.scale_max = 1.6
	process.damping_min = 0.2
	process.damping_max = 0.8
	particles.process_material = process
	particles.draw_pass_1 = _droplet
	particles.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	parent.add_child(particles)
	return particles
