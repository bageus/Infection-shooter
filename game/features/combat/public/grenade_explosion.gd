extends RefCounted
const ATLAS := preload("res://game/core/vfx/public/surface_atlases.gd")

const RADIUS := 5.5
const MARK_LIFETIME := 25.0
const SCORCH_SIZE_MIN := 2.55
const SCORCH_SIZE_MAX := 4.05
const EXPLOSION_V1 := preload("res://game/features/combat/grenade_explosion_v1.tscn")


## True when a static wall stands between a blast centre and the body.
static func is_sheltered(world: World3D, from: Vector3, body: Node3D) -> bool:
	var target := body.global_position + Vector3.UP * 0.5
	var excluded: Array[RID] = []
	if body is CollisionObject3D:
		excluded.append((body as CollisionObject3D).get_rid())
	for _attempt in 6:
		var query := PhysicsRayQueryParameters3D.create(from, target, 1, excluded)
		var hit := world.direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return false
		var collider := hit.get("collider") as CollisionObject3D
		if collider == null:
			return false
		# Only real walls shelter: not the target's own body-part hitboxes
		# (static bodies on its bones) and nothing that takes bullet hits.
		var own_part := body.is_ancestor_of(collider)
		if collider is StaticBody3D and not own_part and not collider.has_method("take_projectile_hit"):
			return true
		excluded.append(collider.get_rid())
	return false


static func explode(projectile: Node3D, location: Vector3, normal: Vector3, contact: Object, scene: Node3D, impacts: Node) -> void:
	if not is_instance_valid(scene):
		return
	var effect := EXPLOSION_V1.instantiate() as Node3D
	scene.add_child(effect)
	effect.global_position = location
	effect.call("start", normal)
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
		# Walls shelter whoever stands behind them.
		if collider != contact and is_sheltered(projectile.get_world_3d(), location + normal * 0.25, body):
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
		elif collider.has_method("take_blast_damage"):
			# Infected: tears limbs away from the blast centre.
			collider.call("take_blast_damage", 155.0 * factor, location)
		elif collider.has_method("apply_blast_stun"):
			collider.call("take_damage", 155.0 * factor, "fire") # the player: elemental (Hardened Tissue)
		elif collider.has_method("take_damage"):
			collider.call("take_damage", 155.0 * factor)
		if collider is RigidBody3D and not (collider as RigidBody3D).freeze:
			(collider as RigidBody3D).apply_central_impulse(direction * (2.0 + 5.0 * factor))
		if collider.has_method("apply_blast_stun") and float(collider.get("health")) > 0.0:
			collider.call("apply_blast_stun", 3.0 + 2.0 * factor, factor)
	if contact != null and (not contact.has_method("take_projectile_hit") or contact.has_method("get_projectile_material") and str(contact.call("get_projectile_material")) in ["concrete", "metal"]):
		_scorch(scene, location, normal, impacts)
	# Surrounding structural surfaces also receive small radial black marks.
	for direction in [Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var trace := PhysicsRayQueryParameters3D.create(location + direction * 0.08, location + direction * 2.7, 7)
		var surface := projectile.get_world_3d().direct_space_state.intersect_ray(trace)
		if not surface.is_empty() and not surface["collider"].has_method("take_projectile_hit"):
			_scorch(scene, surface["position"], surface["normal"], impacts)


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


static func _scorch(scene: Node3D, hit_position: Vector3, normal: Vector3, pool: Node) -> void:
	if normal.length_squared() < 0.1:
		return
	var mark := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * randf_range(SCORCH_SIZE_MIN, SCORCH_SIZE_MAX)
	var material := ATLAS.material(ATLAS.BULLET, randi_range(5, 7))
	quad.material = material
	mark.mesh = quad
	scene.add_child(mark)
	mark.global_position = hit_position + normal * 0.023
	mark.global_basis = Basis.looking_at(-normal, Vector3.FORWARD if absf(normal.y) > 0.9 else Vector3.UP)
	if pool != null and pool.has_method("register_mark"):
		pool.call("register_mark", mark)
	# A direct callable disconnects automatically if the impact budget removes the mark first.
	scene.get_tree().create_timer(MARK_LIFETIME).timeout.connect(mark.queue_free)
