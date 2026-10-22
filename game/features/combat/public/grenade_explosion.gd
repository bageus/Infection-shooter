extends RefCounted
const SURFACE_ATLASES := preload("res://game/core/vfx/public/surface_atlases.gd")
const TRACE := preload("res://game/features/combat/public/explosion_trace.gd")

const RADIUS := 4.0
const OBJECT_DAMAGE := 380.0 # Full-strength hit on a prop; scaled by distance falloff and power.
const CREATURE_DAMAGE := 155.0
const MOUNT_CLEARANCE := 0.35
const QUERY_BATCH := 64
const MAX_QUERY_PASSES := 24
const MARK_LIFETIME := 25.0
const SCORCH_SIZE_MIN := 2.55
const SCORCH_SIZE_MAX := 4.05
const EXPLOSION_V1 := preload("res://game/features/combat/grenade_explosion_v1.tscn")
const DANGER_ZONE := preload("res://game/features/combat/public/floor_danger_zone.gd")
const ZONE_DELAY := 0.35
const ZONE_LIFETIME := 2.2


## True when a static wall stands between a blast centre and the body.
static func is_sheltered(world: World3D, from: Vector3, body: Node3D) -> bool:
	var target := body.global_position + Vector3.UP * 0.5
	var excluded: Array[RID] = []
	if body is CollisionObject3D:
		excluded.append((body as CollisionObject3D).get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, target, 1, excluded)
	var hit := world.direct_space_state.intersect_ray(query)
	# Each pass excludes a distinct non-wall body. Only an empty ray proves
	# the remaining path clear; an arbitrary attempt limit can hide a wall.
	while not hit.is_empty():
		var collider := hit.get("collider") as CollisionObject3D
		if collider == null:
			return false
		# A wall the body hangs on touches it; that is not a wall in front of it.
		if from.distance_to(hit.get("position") as Vector3) > from.distance_to(target) - MOUNT_CLEARANCE:
			return false
		# Only real walls shelter: not the target's own body-part hitboxes
		# (static bodies on its bones) and nothing that takes bullet hits.
		var own_part := body.is_ancestor_of(collider)
		if collider is StaticBody3D and not own_part and not collider.has_method("take_projectile_hit"):
			return true
		excluded.append(collider.get_rid())
		query.exclude = excluded
		hit = world.direct_space_state.intersect_ray(query)
	return false


## Plays one silent blast under `parent` so the particle, smoke and light pipelines
## compile at load instead of as a freeze on the first real grenade.
static func warm_up(parent: Node3D, point: Vector3) -> void:
	var effect := EXPLOSION_V1.instantiate() as Node3D
	effect.set("muted", true)
	parent.add_child(effect)
	effect.global_position = point
	effect.call("start", Vector3.UP)


static func explode(projectile: Node3D, location: Vector3, normal: Vector3, contact: Object, scene: Node3D, impacts: Node) -> void:
	if not is_instance_valid(scene):
		return
	TRACE.begin("grenade_explode")
	var effect := EXPLOSION_V1.instantiate() as Node3D
	scene.add_child(effect)
	effect.global_position = location
	TRACE.mark("effect instantiated")
	effect.call("start", normal)
	TRACE.mark("effect started (particles, light, sound)")
	DANGER_ZONE.spawn(scene, projectile.get_world_3d(), location, RADIUS, ZONE_DELAY, ZONE_LIFETIME)
	TRACE.mark("danger zone spawned")
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	query.shape = sphere
	query.transform.origin = location
	query.collision_mask = 7
	var power := 1.0 if projectile.get("damage_multiplier") == null else float(projectile.get("damage_multiplier"))
	var hit_ids := {}
	for hit in blast_hits(projectile.get_world_3d().direct_space_state, query):
		var collider: Object = hit.get("collider")
		if collider == null or hit_ids.has(collider.get_instance_id()):
			continue
		hit_ids[collider.get_instance_id()] = true
		var body := collider as Node3D
		if body == null or not _receives_blast(body):
			continue
		# Walls shelter whoever stands behind them.
		if collider != contact and is_sheltered(projectile.get_world_3d(), location + normal * 0.25, body):
			continue
		var distance := distance_to_shape(collider, int(hit.get("shape", -1)), location, body.global_position)
		var factor := pow(1.0 - clampf(distance / RADIUS, 0.0, 1.0), 1.15) * power
		var direction := (body.global_position - location).normalized()
		if direction.length_squared() < 0.01:
			direction = Vector3.UP
		if not hit_object(collider, int(hit.get("shape", -1)), location, direction, factor):
			if collider.has_method("take_blast_damage"):
				# Infected: tears limbs away from the blast centre.
				collider.call("take_blast_damage", CREATURE_DAMAGE * factor, location)
			elif collider.has_method("apply_blast_stun"):
				collider.call("take_damage", CREATURE_DAMAGE * factor, "fire") # the player: elemental (Hardened Tissue)
			elif collider.has_method("take_damage"):
				collider.call("take_damage", CREATURE_DAMAGE * factor)
		push_body(collider, direction, factor)
		if collider.has_method("apply_blast_stun") and float(collider.get("health")) > 0.0:
			collider.call("apply_blast_stun", 3.0 + 2.0 * factor, factor)
	TRACE.mark("%d bodies in blast processed" % hit_ids.size())
	if contact != null and (not contact.has_method("take_projectile_hit") or contact.has_method("get_projectile_material") and str(contact.call("get_projectile_material")) in ["concrete", "metal"]):
		_scorch(scene, location, normal, impacts, contact as Node3D)
	scorch_surroundings(projectile.get_world_3d(), scene, location, impacts)
	TRACE.mark("scorch done (end of explode)")


## The one way a blast hurts a destructible object, for grenades and the extinguisher alike, so
## it always goes through the prop's own break staging. False when the body takes no object hit.
static func hit_object(collider: Object, shape: int, location: Vector3, direction: Vector3, factor: float) -> bool:
	if collider.has_method("take_projectile_hit_at_shape"):
		collider.call("take_projectile_hit_at_shape", OBJECT_DAMAGE * factor, location, -direction, direction, "GRENADE", shape)
		return true
	if collider.has_method("take_projectile_hit"):
		collider.call("take_projectile_hit", OBJECT_DAMAGE * factor, location, -direction, direction, "GRENADE")
		return true
	return false


static func push_body(collider: Object, direction: Vector3, factor: float) -> void:
	if collider is RigidBody3D and not (collider as RigidBody3D).freeze:
		(collider as RigidBody3D).apply_central_impulse(direction * (2.0 + 5.0 * factor))


## Radial blast marks on the structure around a point; grenades and extinguisher bursts share it.
static func scorch_surroundings(world: World3D, scene: Node3D, location: Vector3, impacts: Node) -> void:
	for direction in [Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var trace := PhysicsRayQueryParameters3D.create(location + direction * 0.08, location + direction * 2.7, 7)
		var surface := world.direct_space_state.intersect_ray(trace)
		if not surface.is_empty() and not surface["collider"].has_method("take_projectile_hit"):
			_scorch(scene, surface["position"], surface["normal"], impacts, surface["collider"] as Node3D)


## Every body in the blast sphere. Floors and walls own many shapes and would
## fill a single query, so each pass excludes the bodies already found.
static func blast_hits(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var excluded: Array[RID] = []
	for _pass in MAX_QUERY_PASSES:
		query.exclude = excluded
		var batch := space.intersect_shape(query, QUERY_BATCH)
		if batch.is_empty():
			break
		for hit in batch:
			var rid: RID = hit.get("rid", RID())
			if not excluded.has(rid):
				excluded.append(rid)
				found.append(hit)
	return found


static func _receives_blast(body: Node3D) -> bool:
	if body is RigidBody3D and not body.freeze:
		return true
	for method in [&"take_projectile_hit_at_shape", &"take_projectile_hit", &"take_blast_damage", &"apply_blast_stun", &"take_damage"]:
		if body.has_method(method):
			return true
	return false


static func distance_to_shape(collider: Object, shape_index: int, location: Vector3, fallback: Vector3) -> float:
	if collider is CollisionObject3D and shape_index >= 0:
		var physics_body := collider as CollisionObject3D
		var owner := physics_body.shape_owner_get_owner(physics_body.shape_find_owner(shape_index)) as CollisionShape3D
		if owner != null and owner.shape is BoxShape3D:
			var half := (owner.shape as BoxShape3D).size * 0.5
			var local := owner.to_local(location)
			var nearest := Vector3(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y), clampf(local.z, -half.z, half.z))
			return owner.to_global(nearest).distance_to(location)
	return fallback.distance_to(location)


static func _scorch(scene: Node3D, hit_position: Vector3, normal: Vector3, pool: Node, collider: Node3D = null) -> void:
	if normal.length_squared() < 0.1:
		return
	if collider == null or pool == null:
		return
	if collider.has_method("get_projectile_material") and collider.call("get_projectile_material", -1) == "glass":
		return
	if pool.has_method("bake_surface_hit"):
		var surface: Dictionary = pool.call("resolve_surface", collider, hit_position, -normal)
		if pool.call("bake_surface_hit", collider, hit_position, normal, "GRENADE", surface.get("anchor") as MeshInstance3D): return
	var up := Vector3.FORWARD if absf(normal.y) > .9 else Vector3.UP
	var basis := Basis.looking_at(-normal, up).rotated(normal, randf() * TAU)
	var projector := Transform3D(basis, hit_position)
	var material := SURFACE_ATLASES.material(SURFACE_ATLASES.BULLET, randi_range(5, 7))
	material.set_shader_parameter("opacity", .82)
	var marks: Array = pool.call("project_surface", collider, projector, Vector2.ONE * randf_range(SCORCH_SIZE_MIN, SCORCH_SIZE_MAX), material, .18, true)
	for mark in marks:
		pool.call("register_mark", mark)
		scene.get_tree().create_timer(MARK_LIFETIME).timeout.connect(mark.queue_free)
