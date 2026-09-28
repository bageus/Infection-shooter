extends Node3D

const EXPLOSION := preload("res://game/features/combat/public/grenade_explosion.gd")
const GRAVITY := 17.0
const SPEED := 22.0

var shooter: CollisionObject3D
var _velocity := Vector3.ZERO
var _lifetime := 4.0
var _exploded := false


func setup(target: Vector3, firing_body: CollisionObject3D) -> void:
	shooter = firing_body
	var offset := target - global_position
	var horizontal := Vector3(offset.x, 0, offset.z)
	var duration := maxf(0.25, horizontal.length() / SPEED)
	var rise := clampf((offset.y + 0.5 * GRAVITY * duration * duration) / duration, 3.0, 12.0)
	_velocity = horizontal.normalized() * SPEED + Vector3.UP * rise
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.14, 0.17, 0.12)
	material.metallic = 0.65
	mesh.material = material
	var ball := MeshInstance3D.new()
	ball.mesh = mesh
	add_child(ball)


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_lifetime -= delta
	var displacement := _velocity * delta + Vector3.DOWN * (0.5 * GRAVITY * delta * delta)
	var next := global_position + displacement
	var cast := PhysicsRayQueryParameters3D.create(global_position, next, 7)
	if shooter != null and is_instance_valid(shooter):
		cast.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(cast)
	if not hit.is_empty():
		_exploded = true
		call_deferred("_explode_at", hit["position"], hit["normal"], hit["collider"])
		return
	global_position = next
	_velocity += Vector3.DOWN * GRAVITY * delta
	if _lifetime <= 0.0:
		_exploded = true
		call_deferred("_explode_at", global_position, Vector3.UP, null)


func _explode_at(location: Vector3, normal: Vector3, collider: Object) -> void:
	EXPLOSION.explode(self, location, normal, collider if is_instance_valid(collider) else null)
	queue_free()
