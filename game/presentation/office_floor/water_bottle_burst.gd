extends RefCounted
## A shot cooler bottle bursts and spills its water; it never drops off whole.
const PET_MATERIAL := "transparent_pet_bottle"
const WATER := Color(0.62, 0.84, 0.96, 0.55)
const OUTLINE_POINTS := 28


static func find_bottle(meshes: Array) -> int:
	for index in meshes.size():
		var mesh := meshes[index] as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface)
			if material != null and PET_MATERIAL in material.resource_name.to_lower():
				return index
	return -1


static func burst(host: Node3D, mesh: MeshInstance3D, shape: CollisionShape3D, effects: Node3D, _hit_position: Vector3, direction: Vector3) -> void:
	if not is_instance_valid(mesh) or not mesh.visible:
		return
	mesh.hide()
	if is_instance_valid(shape):
		shape.set_deferred("disabled", true)
	var parent: Node3D = effects if is_instance_valid(effects) else host.get_parent() as Node3D
	if parent == null:
		return
	var bounds: AABB = mesh.global_transform * mesh.get_aabb()
	parent.add_child(_splash(bounds.get_center(), direction, bounds.size.y))
	parent.add_child(_puddle(Vector3(bounds.get_center().x, host.global_position.y + 0.012, bounds.get_center().z), maxf(bounds.size.x, bounds.size.z)))


static func _splash(center: Vector3, direction: Vector3, height: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = "BottleSplash"
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.amount = 48
	particles.lifetime = 0.9
	particles.direction = (direction.normalized() + Vector3.UP * 0.5).normalized() if direction.length_squared() > 0.0001 else Vector3.UP
	particles.spread = 55.0
	particles.initial_velocity_min = 1.4
	particles.initial_velocity_max = 3.4
	particles.gravity = Vector3(0, -9.0, 0)
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = maxf(height * 0.25, 0.08)
	var drop := SphereMesh.new()
	drop.radius = 0.02
	drop.height = 0.04
	drop.radial_segments = 6
	drop.rings = 3
	var material := StandardMaterial3D.new()
	material.albedo_color = WATER
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material = material
	particles.mesh = drop
	particles.position = center
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
	return particles


## Irregular spill outline: a lumpy, stretched and rotated blob, unique per puddle.
static func puddle_outline(rng: RandomNumberGenerator, radius: float) -> PackedVector2Array:
	var phase_a := rng.randf() * TAU
	var phase_b := rng.randf() * TAU
	var phase_c := rng.randf() * TAU
	var stretch := rng.randf_range(0.55, 1.0)
	var turn := rng.randf() * TAU
	var points := PackedVector2Array()
	for i in OUTLINE_POINTS:
		var a := TAU * float(i) / OUTLINE_POINTS
		var wobble := 1.0 + 0.2 * sin(2.0 * a + phase_a) + 0.12 * sin(3.0 * a + phase_b) + 0.07 * sin(5.0 * a + phase_c) + rng.randf_range(-0.05, 0.05)
		var point := Vector2(cos(a) * radius * wobble, sin(a) * radius * wobble * stretch)
		points.append(point.rotated(turn))
	return points


static func puddle_mesh(rng: RandomNumberGenerator, radius: float) -> ArrayMesh:
	var outline := puddle_outline(rng, radius)
	var vertices := PackedVector3Array([Vector3.ZERO])
	var normals := PackedVector3Array([Vector3.UP])
	for point in outline:
		vertices.append(Vector3(point.x, 0.0, point.y))
		normals.append(Vector3.UP)
	var indices := PackedInt32Array()
	for i in outline.size():
		indices.append_array([0, 1 + (i + 1) % outline.size(), 1 + i])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _puddle(position: Vector3, diameter: float) -> MeshInstance3D:
	var puddle := MeshInstance3D.new()
	puddle.name = "WaterPuddle"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var disc := puddle_mesh(rng, diameter * 0.9)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(WATER.r, WATER.g, WATER.b, 0.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.05
	material.metallic_specular = 0.9
	disc.surface_set_material(0, material)
	puddle.mesh = disc
	puddle.position = position
	puddle.scale = Vector3(0.2, 1.0, 0.2)
	puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tween := puddle.create_tween()
	tween.set_parallel(true)
	tween.tween_property(puddle, "scale", Vector3.ONE, 3.0).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.42, 0.6)
	tween.chain().tween_interval(25.0)
	tween.chain().tween_property(material, "albedo_color:a", 0.0, 6.0)
	tween.chain().tween_callback(puddle.queue_free)
	return puddle
