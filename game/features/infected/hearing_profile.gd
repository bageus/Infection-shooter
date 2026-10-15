extends Resource
## Authored acoustic occlusion settings; immutable during play.
@export_flags_3d_physics var wall_mask := 1
@export var ear_height := 1.5
@export var alert_radius := 16.0
@export var investigate_refresh_distance := 2.0
@export_range(1, 32) var max_ray_hits := 16


func reaches(actor: Node3D, source: Vector3, radius: float) -> bool:
	if actor.global_position.distance_to(source) > radius:
		return false
	var excluded: Array[RID] = []
	if actor is CollisionObject3D:
		excluded.append((actor as CollisionObject3D).get_rid())
	var from := actor.global_position + Vector3.UP * ear_height
	var space := actor.get_world_3d().direct_space_state
	for _i in max_ray_hits:
		var query := PhysicsRayQueryParameters3D.create(from, source, wall_mask, excluded)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return true
		var collider: Object = hit.collider
		if not (collider is CharacterBody3D or collider is RigidBody3D or (collider is Node and collider.is_in_group("infected_breakable_glass"))):
			return false
		excluded.append(hit.rid)
	return false
