extends RefCounted

const RAYS := 24
const RADIUS := 3.2
const HEIGHT := 0.8


# Masks for recent cloud spots: a crowd dying in one place (one grenade)
# shares one mask. Entries live a few seconds, so walls the planner moved or
# a blast broke are never clipped against a stale mask.
static var _cache: Dictionary = {}
const CACHE_SECONDS := 3.0


static func texture_for(cloud: Area3D) -> ImageTexture:
	var now := Time.get_ticks_msec() / 1000.0
	var key := (cloud.global_position * 2.0).round()
	var entry: Array = _cache.get(key, [])
	if not entry.is_empty() and now - float(entry[0]) < CACHE_SECONDS:
		return entry[1]
	for old_key in _cache.keys():
		if now - float(_cache[old_key][0]) >= CACHE_SECONDS:
			_cache.erase(old_key)
	var texture := _build_texture(cloud)
	_cache[key] = [now, texture]
	return texture


static func _build_texture(cloud: Area3D) -> ImageTexture:
	var image := Image.create(RAYS, 1, false, Image.FORMAT_RF)
	var origin := cloud.global_position + Vector3.UP * HEIGHT
	for index in RAYS:
		var angle := (float(index) + 0.5) * TAU / float(RAYS) - PI
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var distance := barrier_distance(cloud.get_world_3d(), origin, origin + direction * RADIUS)
		image.set_pixel(index, 0, Color(distance / RADIUS, 0.0, 0.0))
	return ImageTexture.create_from_image(image)


static func clear_to(cloud: Area3D, body: Node3D) -> bool:
	var ignored: Array[RID] = []
	if body is CollisionObject3D:
		ignored.append((body as CollisionObject3D).get_rid())
	var origin := cloud.global_position + Vector3.UP * HEIGHT
	var target := body.global_position + Vector3.UP * HEIGHT
	return barrier_distance(cloud.get_world_3d(), origin, target, ignored) >= origin.distance_to(target) - 0.03


static func barrier_distance(world: World3D, origin: Vector3, target: Vector3, ignored: Array[RID] = []) -> float:
	var distance := origin.distance_to(target)
	var excluded := ignored.duplicate()
	for _attempt in 8:
		var query := PhysicsRayQueryParameters3D.create(origin, target, 1, excluded)
		var hit: Dictionary = world.direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return distance
		var collider := hit.get("collider") as CollisionObject3D
		if collider == null:
			return distance
		if collider is StaticBody3D or (collider is RigidBody3D and str(collider.get("model_path")).contains("/enviroments/01/")):
			return origin.distance_to(hit["position"] as Vector3)
		excluded.append(collider.get_rid())
	return distance
