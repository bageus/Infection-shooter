extends RefCounted

const RADIUS := 5.5
const MARK_LIFETIME := 25.0
static var scorch_texture: Texture2D


static func explode(projectile: Node3D, location: Vector3, normal: Vector3, contact: Object) -> void:
	var scene := projectile.get_tree().current_scene as Node3D
	if scene == null:
		return
	_flash(scene, location)
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	query.shape = sphere
	query.transform.origin = location
	query.collision_mask = 7
	var hit_ids := {}
	for hit in projectile.get_world_3d().direct_space_state.intersect_shape(query, 256):
		var collider: Object = hit.get("collider")
		if collider == null or hit_ids.has(collider.get_instance_id()):
			continue
		hit_ids[collider.get_instance_id()] = true
		var body := collider as Node3D
		if body == null:
			continue
		var distance := _distance_to_shape(collider, int(hit.get("shape", -1)), location, body.global_position)
		var factor := pow(1.0 - clampf(distance / RADIUS, 0.0, 1.0), 1.15)
		var direction := (body.global_position - location).normalized()
		if direction.length_squared() < 0.01:
			direction = Vector3.UP
		if collider.has_method("take_projectile_hit_at_shape"):
			collider.call("take_projectile_hit_at_shape", 380.0 * factor, location, -direction, direction, "GRENADE", int(hit.get("shape", -1)))
		elif collider.has_method("take_projectile_hit"):
			collider.call("take_projectile_hit", 380.0 * factor, location, -direction, direction, "GRENADE")
		elif collider.has_method("take_damage"):
			collider.call("take_damage", 155.0 * factor)
		if collider is RigidBody3D and not (collider as RigidBody3D).freeze:
			(collider as RigidBody3D).apply_central_impulse(direction * (2.0 + 5.0 * factor))
		if collider.has_method("apply_blast_stun") and float(collider.get("health")) > 0.0:
			collider.call("apply_blast_stun", 3.0 + 2.0 * factor, factor)
	if contact != null and (not contact.has_method("take_projectile_hit") or contact.has_method("get_projectile_material") and str(contact.call("get_projectile_material")) in ["concrete", "metal"]):
		_scorch(scene, location, normal)
	# Surrounding structural surfaces also receive small radial black marks.
	for direction in [Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var trace := PhysicsRayQueryParameters3D.create(location + direction * 0.08, location + direction * 2.7, 7)
		var surface := projectile.get_world_3d().direct_space_state.intersect_ray(trace)
		if not surface.is_empty() and not surface["collider"].has_method("take_projectile_hit"):
			_scorch(scene, surface["position"], surface["normal"])


static func _distance_to_shape(collider: Object, shape_index: int, location: Vector3, fallback: Vector3) -> float:
	if collider is CollisionObject3D and shape_index >= 0:
		var physics_body := collider as CollisionObject3D
		var owner := physics_body.shape_owner_get_owner(physics_body.shape_find_owner(shape_index)) as CollisionShape3D
		if owner != null and owner.shape is BoxShape3D:
			var half := (owner.shape as BoxShape3D).size * 0.5
			var local := owner.to_local(location)
			var nearest := Vector3(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y), clampf(local.z, -half.z, half.z))
			return owner.to_global(nearest).distance_to(location)
	return fallback.distance_to(location)


static func _flash(scene: Node3D, location: Vector3) -> void:
	var burst := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.45, 0.08, 0.5)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.33, 0.03)
	glow.emission_energy_multiplier = 4.0
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = glow
	burst.mesh = mesh
	scene.add_child(burst)
	burst.global_position = location
	var tween := burst.create_tween()
	tween.tween_property(burst, "scale", Vector3.ONE * RADIUS * 1.5, 0.28)
	tween.tween_callback(burst.queue_free)
	var smoke := GPUParticles3D.new()
	smoke.amount = 64
	smoke.lifetime = 1.1
	smoke.one_shot = true
	smoke.explosiveness = 1.0
	var process := ParticleProcessMaterial.new()
	process.spread = 180.0
	process.initial_velocity_min = 3.0
	process.initial_velocity_max = 7.0
	process.gravity = Vector3(0, -3, 0)
	smoke.process_material = process
	var puff := SphereMesh.new()
	puff.radius = 0.12
	puff.height = 0.24
	var soot := StandardMaterial3D.new()
	soot.albedo_color = Color(0.14, 0.13, 0.12, 0.65)
	soot.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.material = soot
	smoke.draw_pass_1 = puff
	scene.add_child(smoke)
	smoke.global_position = location
	smoke.emitting = true
	scene.get_tree().create_timer(2.0).timeout.connect(smoke.queue_free)


static func _scorch(scene: Node3D, hit_position: Vector3, normal: Vector3) -> void:
	if normal.length_squared() < 0.1:
		return
	if scorch_texture == null:
		var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var radius := Vector2(x - 32, y - 32).length() / 32.0
				image.set_pixel(x, y, Color(0.035, 0.028, 0.023, pow(maxf(0.0, 1.0 - radius), 1.6) * 0.88))
		scorch_texture = ImageTexture.create_from_image(image)
	var mark := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * randf_range(0.85, 1.35)
	var material := StandardMaterial3D.new()
	material.albedo_texture = scorch_texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = 1
	quad.material = material
	mark.mesh = quad
	scene.add_child(mark)
	mark.global_position = hit_position + normal * 0.023
	mark.global_basis = Basis.looking_at(-normal, Vector3.FORWARD if absf(normal.y) > 0.9 else Vector3.UP)
	var pool := scene.get_node_or_null("ImpactEffects")
	if pool != null and pool.has_method("register_mark"):
		pool.call("register_mark", mark)
	scene.get_tree().create_timer(MARK_LIFETIME).timeout.connect(func() -> void:
		if is_instance_valid(mark): mark.queue_free()
	)
