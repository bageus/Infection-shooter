extends Node3D

const EXPLOSION := preload("res://game/features/combat/public/grenade_explosion.gd")
const PROJECTILE_VISUAL := preload("res://game/features/combat/projectile_visual.gd")
const GRAVITY := 17.0
const SPEED := 22.0

var shooter: CollisionObject3D
var _velocity := Vector3.ZERO
var _lifetime := 4.0
var _exploded := false
var collision_origin := Vector3.INF
var _visual: Node3D

var effects_root: Node3D
var impact_pool: Node


# Public scene wiring v1; owned by the mission composition.
func configure_world(container: Node3D, impacts: Node) -> void:
	effects_root = container
	impact_pool = impacts


func setup(target: Vector3, firing_body: CollisionObject3D) -> void:
	shooter = firing_body
	_velocity = launch_velocity(global_position, target)
	_visual = PROJECTILE_VISUAL.new() as Node3D
	add_child(_visual)
	_visual.call("configure", "GRENADE LAUNCHER", _velocity)


static func launch_velocity(origin: Vector3, target: Vector3) -> Vector3:
	var offset := target - origin
	var horizontal := Vector3(offset.x, 0, offset.z)
	# Short targets need a slower horizontal launch, otherwise the projectile
	# overshoots before gravity can bring it back to the cursor's surface.
	var duration := clampf(horizontal.length() / SPEED, 0.42, 1.6)
	var rise := (offset.y + 0.5 * GRAVITY * duration * duration) / duration
	return horizontal / duration + Vector3.UP * rise


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_lifetime -= delta
	var displacement := _velocity * delta + Vector3.DOWN * (0.5 * GRAVITY * delta * delta)
	var next := global_position + displacement
	var from_barrel := collision_origin.is_finite()
	var cast := PhysicsRayQueryParameters3D.create(collision_origin if collision_origin.is_finite() else global_position, next, 7)
	cast.hit_from_inside = from_barrel
	collision_origin = Vector3.INF
	if shooter != null and is_instance_valid(shooter):
		cast.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(cast)
	if not hit.is_empty():
		if (hit["normal"] as Vector3).is_zero_approx():
			hit["normal"] = -_velocity.normalized()
		_exploded = true
		call_deferred("_explode_at", hit["position"], hit["normal"], hit["collider"])
		return
	global_position = next
	_velocity += Vector3.DOWN * GRAVITY * delta
	_visual.call("set_direction", _velocity)
	if _lifetime <= 0.0:
		_exploded = true
		call_deferred("_explode_at", global_position, Vector3.UP, null)


func _explode_at(location: Vector3, normal: Vector3, collider: Object) -> void:
	EXPLOSION.explode(self, location, normal, collider if is_instance_valid(collider) else null, effects_root, impact_pool)
	queue_free()
