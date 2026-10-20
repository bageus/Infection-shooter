extends RefCounted
## Floor warning for a blast that is about to go off: a ring and a faint disc
## on the floor at the blast radius. It fades in after `delay`, so the player
## learns the radius from what they see, and fades out when `lifetime` ends.

const FADE := 0.25
const FLOOR_MASK := 7
const MAX_SURFACES := 8
const LIFT := 0.03
const SHADER := preload("res://game/features/combat/floor_danger_zone.gdshader")

static var _material: ShaderMaterial


## Puts the zone on the floor under `point` and runs its fade. `lifetime` counts
## from spawn to removal, fades included. Callers pass a valid `parent`.
static func spawn(parent: Node3D, world: World3D, point: Vector3, radius: float, delay: float, lifetime: float) -> void:
	var zone := Node3D.new()
	var meshes: Array[MeshInstance3D] = [_surface(radius)]
	zone.add_child(meshes[0])
	parent.add_child(zone)
	zone.global_position = floor_point(world, point) + Vector3.UP * LIFT
	_set_strength(0.0, meshes)
	var tween := zone.create_tween()
	tween.tween_interval(delay)
	tween.tween_method(_set_strength.bind(meshes), 0.0, 1.0, FADE)
	tween.tween_interval(maxf(lifetime - delay - 2.0 * FADE, 0.0))
	tween.tween_method(_set_strength.bind(meshes), 1.0, 0.0, FADE)
	tween.tween_callback(zone.queue_free)


## The lowest surface under the impact: desk tops and props are passed through, so the zone lies on the floor.
static func floor_point(world: World3D, point: Vector3) -> Vector3:
	var exclude: Array[RID] = []
	var floor_at := point
	for _attempt in MAX_SURFACES:
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.4, point + Vector3.DOWN * 8.0, FLOOR_MASK, exclude)
		var hit := world.direct_space_state.intersect_ray(query)
		if hit.is_empty():
			break
		floor_at = hit.position as Vector3
		exclude.append(hit.rid as RID)
	return floor_at


static func _set_strength(strength: float, meshes: Array[MeshInstance3D]) -> void:
	for mesh in meshes:
		mesh.set_instance_shader_parameter(&"fade", strength)


# One quad carries the whole zone; the shader draws the thin ring, the fill and the waves.
static func _surface(radius: float) -> MeshInstance3D:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 2.0
	var instance := MeshInstance3D.new()
	instance.mesh = plane
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.material_override = _material
	return instance
