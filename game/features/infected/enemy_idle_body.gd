extends RefCounted
## Cached capsule geometry and a cheap support probe for idle simulation.
const ACTOR := preload("res://game/features/infected/infected_capsule.gd")
var _radius := 0.35
var _height := 1.8
var _shape: Shape3D
var _scale := -1.0
var _query: PhysicsRayQueryParameters3D

func radius(shape_node: CollisionShape3D, body_scale: float) -> float:
	var shape: Shape3D = shape_node.shape if shape_node != null else null
	if shape != _shape:
		if _shape != null:
			_shape.changed.disconnect(_invalidate)
		_shape = shape
		if shape != null:
			shape.changed.connect(_invalidate)
		_scale = -1.0
	if body_scale != _scale:
		_scale = body_scale
		_radius = (shape as CapsuleShape3D).radius * body_scale if shape is CapsuleShape3D else 0.35
		_height = (shape as CapsuleShape3D).height if shape is CapsuleShape3D else 1.8
	return _radius

func _invalidate() -> void:
	_scale = -1.0

func supported(actor: ACTOR) -> bool:
	# The center probe is conservative at ledges: if only the capsule rim is
	# supported, fall back to normal sliding rather than trusting stale floor state.
	var shape_node: CollisionShape3D = actor.collision_shape
	if shape_node == null or shape_node.disabled or not shape_node.shape is CapsuleShape3D:
		return false
	radius(shape_node, actor.global_basis.x.length())
	if _query == null:
		_query = PhysicsRayQueryParameters3D.new()
		_query.exclude = [actor.get_rid()]
	var foot := shape_node.global_position - shape_node.global_basis.y * (_height * 0.5)
	_query.from = foot + Vector3.UP * 0.02
	_query.to = foot + Vector3.DOWN * 0.06
	_query.collision_mask = actor.collision_mask
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(_query)
	return not hit.is_empty() and (hit.normal as Vector3).dot(actor.up_direction) >= cos(actor.floor_max_angle)
